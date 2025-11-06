use crate::{config::Config, proto, router::Router, types::{ChatMessage, ChatRequest as InternalChatRequest}};
use anyhow::Result;
use std::sync::Arc;
use tonic::{transport::Server, Request, Response, Status};
use tracing::{info, error};

/// gRPC service implementation
pub struct ThanosServiceImpl {
    config: Arc<Config>,
    router: Arc<Router>,
}

#[tonic::async_trait]
impl proto::thanos_service_server::ThanosService for ThanosServiceImpl {
    type ChatCompletionStream =
        tokio_stream::wrappers::ReceiverStream<Result<proto::ChatResponse, Status>>;

    async fn chat_completion(
        &self,
        request: Request<proto::ChatRequest>,
    ) -> Result<Response<Self::ChatCompletionStream>, Status> {
        let proto_req = request.into_inner();

        info!("gRPC chat completion request: model={}", proto_req.model);

        // Convert proto request to internal type
        let internal_req = proto_to_internal_request(proto_req)
            .map_err(|e| Status::invalid_argument(format!("Invalid request: {}", e)))?;

        let (tx, rx) = tokio::sync::mpsc::channel(100);

        // If streaming is requested, use stream routing
        if internal_req.stream {
            let router = Arc::clone(&self.router);

            tokio::spawn(async move {
                match router.route_chat_completion_stream(&internal_req).await {
                    Ok(mut stream_rx) => {
                        // Forward stream chunks from router to gRPC client
                        while let Some(chunk_result) = stream_rx.recv().await {
                            match chunk_result {
                                Ok(response) => {
                                    let proto_response = internal_to_proto_response(response);
                                    if tx.send(Ok(proto_response)).await.is_err() {
                                        break; // Client disconnected
                                    }
                                }
                                Err(e) => {
                                    error!("Stream error: {}", e);
                                    let _ = tx.send(Err(Status::internal(format!("Stream error: {}", e)))).await;
                                    break;
                                }
                            }
                        }
                    }
                    Err(e) => {
                        error!("Failed to route stream: {}", e);
                        let _ = tx.send(Err(Status::internal(format!("Routing failed: {}", e)))).await;
                    }
                }
            });
        } else {
            // Non-streaming: make single request and send as final chunk
            let router = Arc::clone(&self.router);

            tokio::spawn(async move {
                match router.route_chat_completion(&internal_req).await {
                    Ok(response) => {
                        let proto_response = internal_to_proto_response(response);
                        let _ = tx.send(Ok(proto_response)).await;
                    }
                    Err(e) => {
                        error!("Failed to route request: {}", e);
                        let _ = tx.send(Err(Status::internal(format!("Routing failed: {}", e)))).await;
                    }
                }
            });
        }

        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }

    async fn list_models(
        &self,
        _request: Request<proto::Empty>,
    ) -> Result<Response<proto::ModelsResponse>, Status> {
        // Collect models from all enabled providers
        let providers = self.config.enabled_providers();
        let mut models = Vec::new();

        for (provider_name, provider_config) in providers {
            // Add the configured model for this provider (if it exists)
            if let Some(ref model_id) = provider_config.model {
                models.push(proto::ModelInfo {
                    id: format!("{}/{}", provider_name, model_id),
                    provider: provider_name.clone(),
                    name: model_id.clone(),
                    context_length: 128000, // Default, could be fetched from models.dev
                    max_output: 4096,
                    supports_streaming: true,
                    supports_functions: true,
                    supports_vision: false,
                });
            }
        }

        Ok(Response::new(proto::ModelsResponse { models }))
    }

    async fn health(
        &self,
        _request: Request<proto::Empty>,
    ) -> Result<Response<proto::HealthResponse>, Status> {
        // Check health of all enabled providers
        let providers = self.config.enabled_providers();
        let mut provider_healths = Vec::new();

        for (provider_name, _provider_config) in providers {
            // For now, just return healthy status
            // TODO: Actually ping providers to check health
            provider_healths.push(proto::ProviderHealth {
                name: provider_name,
                status: "healthy".to_string(),
                error: None,
            });
        }

        let status = "healthy".to_string();

        Ok(Response::new(proto::HealthResponse {
            status,
            providers: provider_healths,
            uptime: 0, // TODO: Track uptime from server start time
        }))
    }
}

/// Convert proto request to internal request type
fn proto_to_internal_request(proto_req: proto::ChatRequest) -> anyhow::Result<InternalChatRequest> {
    let messages: Vec<ChatMessage> = proto_req
        .messages
        .into_iter()
        .map(|msg| {
            // Convert string role to Role enum
            let role = match msg.role.to_lowercase().as_str() {
                "system" => crate::types::Role::System,
                "user" => crate::types::Role::User,
                "assistant" => crate::types::Role::Assistant,
                _ => crate::types::Role::User, // Default to user if unknown
            };
            ChatMessage {
                role,
                content: msg.content,
            }
        })
        .collect();

    Ok(InternalChatRequest {
        model: proto_req.model,
        messages,
        stream: proto_req.stream,
        temperature: proto_req.temperature,
        max_tokens: proto_req.max_tokens,
        top_p: proto_req.top_p,
        system: proto_req.system,
    })
}

/// Convert internal response to proto response type
fn internal_to_proto_response(response: crate::types::ChatResponse) -> proto::ChatResponse {
    proto::ChatResponse {
        provider: response.provider,
        model: response.model,
        content: response.content,
        done: response.done,
        usage: response.usage.map(|u| proto::Usage {
            prompt_tokens: u.prompt_tokens,
            completion_tokens: u.completion_tokens,
            total_tokens: u.total_tokens,
        }),
        finish_reason: response.finish_reason,
    }
}

/// Start gRPC server with advanced features
pub async fn serve(config: Config) -> Result<()> {
    let addr = config.server.grpc.parse()?;

    let config_arc = Arc::new(config.clone());
    let router = Arc::new(Router::new(Arc::clone(&config_arc)));

    let service = ThanosServiceImpl {
        config: config_arc,
        router,
    };

    info!("✓ gRPC server listening on {}", addr);

    // Build server with advanced features
    let mut server = Server::builder()
        // Enable TCP keepalive
        .tcp_keepalive(Some(std::time::Duration::from_secs(60)))
        // Set connection timeout
        .timeout(std::time::Duration::from_secs(300))
        // Add service with compression and message size limits
        .add_service(
            proto::thanos_service_server::ThanosServiceServer::new(service)
                // Enable gzip compression for bandwidth optimization
                .accept_compressed(tonic::codec::CompressionEncoding::Gzip)
                .send_compressed(tonic::codec::CompressionEncoding::Gzip)
                // Set max message size (256MB for large requests/responses)
                .max_decoding_message_size(256 * 1024 * 1024)
                .max_encoding_message_size(256 * 1024 * 1024),
        );

    // Add gRPC reflection for introspection (useful for grpcurl, Postman, etc.)
    #[cfg(debug_assertions)]
    {
        let reflection_service = tonic_reflection::server::Builder::configure()
            .register_encoded_file_descriptor_set(proto::FILE_DESCRIPTOR_SET)
            .build()?;

        server = server.add_service(reflection_service);
        info!("gRPC reflection enabled (debug mode)");
    }

    // TODO: For production, add TLS:
    // let tls_config = load_tls_config(...)?;
    // server = server.tls_config(tls_config)?;

    server.serve(addr).await?;

    Ok(())
}

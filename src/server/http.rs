use crate::config::Config;
use crate::health::HealthChecker;
use crate::router::Router as ThanosRouter;
use crate::types::ChatRequest;
use anyhow::Result;
use axum::{
    extract::State,
    http::StatusCode,
    response::{sse::Event, IntoResponse, Json, Sse},
    routing::{get, post},
    Router,
};
use serde_json::{json, Value};
use std::{convert::Infallible, sync::Arc};
use tower_http::{
    compression::CompressionLayer,
    cors::CorsLayer,
    trace::TraceLayer,
};
use tracing::{error, info};

/// HTTP server state
#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub router: Arc<ThanosRouter>,
    pub health_checker: Arc<HealthChecker>,
}

/// Start HTTP server (OpenAI-compatible API)
pub async fn serve(config: Config) -> Result<()> {
    let config_arc = Arc::new(config.clone());
    let router = Arc::new(ThanosRouter::new(config_arc.clone()));
    let health_checker = Arc::new(HealthChecker::new());

    let state = AppState {
        config: config_arc,
        router,
        health_checker,
    };

    let app = Router::new()
        // Health check
        .route("/health", get(health_handler))
        // Metrics (Prometheus)
        .route("/metrics", get(metrics_handler))
        // List models
        .route("/v1/models", get(models_handler))
        // List providers
        .route("/v1/providers", get(providers_handler))
        // Chat completions (OpenAI-compatible)
        .route("/v1/chat/completions", post(chat_completions_handler))
        // Middleware
        .layer(TraceLayer::new_for_http())
        .layer(CompressionLayer::new())
        .layer(CorsLayer::permissive())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(&config.server.bind).await?;
    info!("✓ HTTP server listening on {}", config.server.bind);

    axum::serve(listener, app).await?;

    Ok(())
}

/// GET /health - Check health of Thanos and all providers
pub async fn health_handler(State(state): State<AppState>) -> Json<Value> {
    use std::collections::HashMap;

    // Get provider endpoints for health checks
    let mut provider_endpoints = HashMap::new();

    for (name, provider_config) in state.config.enabled_providers() {
        let endpoint = match name.as_str() {
            "anthropic" | "anthropic_max" => {
                provider_config.base_url.clone()
                    .unwrap_or_else(|| "https://api.anthropic.com".to_string())
            },
            "openai" => {
                provider_config.base_url.clone()
                    .unwrap_or_else(|| "https://api.openai.com".to_string())
            },
            "gemini" => {
                provider_config.base_url.clone()
                    .unwrap_or_else(|| "https://generativelanguage.googleapis.com".to_string())
            },
            "xai" => {
                provider_config.base_url.clone()
                    .unwrap_or_else(|| "https://api.x.ai".to_string())
            },
            "ollama" => {
                provider_config.endpoint.clone()
                    .unwrap_or_else(|| "http://localhost:11434".to_string())
            },
            "github_copilot" => "https://api.github.com".to_string(),
            _ => continue,
        };
        provider_endpoints.insert(name.clone(), endpoint);
    }

    // Check provider health (runs in parallel)
    let provider_health = state.health_checker.check_all(provider_endpoints).await;

    // Determine overall status
    let overall_status = if provider_health
        .values()
        .all(|h| h.status == crate::health::HealthStatus::Healthy)
    {
        "healthy"
    } else if provider_health
        .values()
        .any(|h| h.status == crate::health::HealthStatus::Healthy)
    {
        "degraded"
    } else {
        "unhealthy"
    };

    Json(json!({
        "status": overall_status,
        "version": crate::VERSION,
        "providers": provider_health,
    }))
}

/// GET /metrics (Prometheus format)
pub async fn metrics_handler() -> String {
    use prometheus::Encoder;
    let encoder = prometheus::TextEncoder::new();
    let metric_families = crate::metrics::METRICS.registry.gather();

    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();

    String::from_utf8(buffer).unwrap()
}

/// GET /v1/providers - List enabled providers
pub async fn providers_handler(State(state): State<AppState>) -> Json<Value> {
    let providers: Vec<Value> = state
        .config
        .enabled_providers()
        .iter()
        .map(|(name, config)| {
            json!({
                "id": name,
                "name": name,
                "auth_method": format!("{:?}", config.auth_method).to_lowercase(),
                "model": config.model.clone().unwrap_or_else(|| "default".to_string()),
                "enabled": config.enabled,
            })
        })
        .collect();

    Json(json!({
        "object": "list",
        "data": providers,
        "count": providers.len(),
    }))
}

/// GET /v1/models
pub async fn models_handler(State(_state): State<AppState>) -> Json<Value> {
    use crate::models_dev::MODELS_DEV_CLIENT;

    // Fetch models from models.dev
    let models = MODELS_DEV_CLIENT.get_all_models();

    let data: Vec<Value> = models
        .iter()
        .map(|m| {
            json!({
                "id": m.id,
                "object": "model",
                "owned_by": m.provider,
                "name": m.name,
                "context_length": m.context_length,
                "output_limit": m.output_limit,
                "pricing": m.pricing.as_ref().map(|p| json!({
                    "input": p.input,
                    "output": p.output,
                    "cache_read": p.cache_read,
                    "reasoning": p.reasoning,
                })),
                "capabilities": {
                    "streaming": m.supports_streaming,
                    "functions": m.supports_functions,
                    "vision": m.supports_vision,
                    "reasoning": m.supports_reasoning,
                }
            })
        })
        .collect();

    Json(json!({
        "object": "list",
        "data": data,
        "count": models.len(),
    }))
}

/// POST /v1/chat/completions (OpenAI-compatible)
pub async fn chat_completions_handler(
    State(state): State<AppState>,
    Json(payload): Json<ChatRequest>,
) -> Result<axum::response::Response, (StatusCode, String)> {
    // Check if streaming is requested
    if payload.stream {
        // Return SSE stream
        match state.router.route_chat_completion_stream(&payload).await {
            Ok(mut rx) => {
                let stream = async_stream::stream! {
                    while let Some(result) = rx.recv().await {
                        match result {
                            Ok(response) => {
                                // Convert to OpenAI SSE format
                                let data = json!({
                                    "id": "chatcmpl-stream",
                                    "object": "chat.completion.chunk",
                                    "created": chrono::Utc::now().timestamp(),
                                    "model": response.model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "content": response.content
                                        },
                                        "finish_reason": response.finish_reason
                                    }]
                                });
                                yield Ok::<_, Infallible>(Event::default().data(data.to_string()));
                            }
                            Err(e) => {
                                error!("Stream error: {}", e);
                                break;
                            }
                        }
                    }

                    // Send [DONE] marker
                    yield Ok::<_, Infallible>(Event::default().data("[DONE]"));
                };

                Ok(Sse::new(stream).into_response())
            }
            Err(e) => {
                error!("Failed to start stream: {}", e);
                Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
            }
        }
    } else {
        // Non-streaming response
        match state.router.route_chat_completion(&payload).await {
            Ok(response) => {
                let openai_response = json!({
                    "id": format!("chatcmpl-{}", uuid::Uuid::new_v4()),
                    "object": "chat.completion",
                    "created": chrono::Utc::now().timestamp(),
                    "model": response.model,
                    "choices": [{
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": response.content
                        },
                        "finish_reason": response.finish_reason.unwrap_or_else(|| "stop".to_string())
                    }],
                    "usage": response.usage.map(|u| json!({
                        "prompt_tokens": u.prompt_tokens,
                        "completion_tokens": u.completion_tokens,
                        "total_tokens": u.total_tokens
                    }))
                });

                Ok(Json(openai_response).into_response())
            }
            Err(e) => {
                error!("Chat completion error: {}", e);
                Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
            }
        }
    }
}

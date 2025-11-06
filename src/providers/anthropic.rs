use crate::providers::Provider;
use crate::types::{ChatRequest, ChatResponse, Role, Usage};
use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

pub struct AnthropicProvider {
    api_key: Option<String>,
    use_oauth: bool,
    base_url: String,
    model: String,
}

impl AnthropicProvider {
    pub fn new(api_key: String, model: String) -> Self {
        Self {
            api_key: Some(api_key),
            use_oauth: false,
            base_url: "https://api.anthropic.com".to_string(),
            model,
        }
    }

    pub fn new_oauth(model: String) -> Self {
        Self {
            api_key: None,
            use_oauth: true,
            base_url: "https://api.anthropic.com".to_string(),
            model,
        }
    }

    pub fn from_config(config: &crate::config::ProviderConfig) -> Result<Self> {
        let model = config.model.clone()
            .unwrap_or_else(|| "claude-sonnet-4-5-20250513".to_string());

        // Check if this is OAuth (anthropic_max) or API key
        if config.auth_method == crate::types::AuthMethod::OAuth {
            Ok(Self::new_oauth(model))
        } else {
            let api_key = config.api_key.clone()
                .ok_or_else(|| anyhow::anyhow!("Anthropic API key not configured"))?;
            Ok(Self::new(api_key, model))
        }
    }

    async fn get_api_key(&self) -> Result<String> {
        if self.use_oauth {
            // Use TokenManager to get/refresh OAuth token
            let token_manager = crate::auth::TokenManager::new();
            token_manager.get_access_token("anthropic_max").await
        } else {
            self.api_key.clone()
                .ok_or_else(|| anyhow::anyhow!("No API key configured"))
        }
    }

    pub async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        <Self as Provider>::chat_completion(self, request).await
    }

    pub async fn chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>> {
        <Self as Provider>::chat_completion_stream(self, request).await
    }
}

// Anthropic API types
#[derive(Serialize)]
struct AnthropicRequest {
    model: String,
    messages: Vec<AnthropicMessage>,
    max_tokens: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    system: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    stream: bool,
}

#[derive(Serialize, Deserialize)]
struct AnthropicMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct AnthropicResponse {
    content: Vec<ContentBlock>,
    usage: AnthropicUsage,
    stop_reason: Option<String>,
}

#[derive(Deserialize)]
struct ContentBlock {
    text: String,
}

#[derive(Deserialize, Debug)]
struct AnthropicUsage {
    input_tokens: i32,
    output_tokens: i32,
}

// Streaming event types
#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
#[serde(rename_all = "snake_case")]
enum StreamEvent {
    MessageStart {
        message: MessageMetadata,
    },
    ContentBlockStart {
        index: i32,
        content_block: ContentBlockStart,
    },
    ContentBlockDelta {
        index: i32,
        delta: ContentDelta,
    },
    ContentBlockStop {
        index: i32,
    },
    MessageDelta {
        delta: MessageDeltaData,
        usage: Option<DeltaUsage>,
    },
    MessageStop,
    Ping,
    #[serde(other)]
    Unknown,
}

#[derive(Deserialize, Debug)]
struct MessageMetadata {
    id: String,
    #[serde(rename = "type")]
    message_type: String,
    role: String,
    model: String,
    usage: AnthropicUsage,
}

#[derive(Deserialize, Debug)]
struct ContentBlockStart {
    #[serde(rename = "type")]
    block_type: String,
    text: Option<String>,
}

#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
#[serde(rename_all = "snake_case")]
enum ContentDelta {
    TextDelta { text: String },
}

#[derive(Deserialize, Debug)]
struct MessageDeltaData {
    stop_reason: Option<String>,
}

#[derive(Deserialize, Debug)]
struct DeltaUsage {
    output_tokens: i32,
}

#[async_trait]
impl Provider for AnthropicProvider {
    fn name(&self) -> &str {
        "anthropic"
    }

    async fn health(&self) -> Result<bool> {
        // Simple health check: verify we can get an API key
        Ok(self.get_api_key().await.is_ok())
    }

    async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let api_key = self.get_api_key().await?;
        let client = reqwest::Client::new();

        // Convert messages
        let messages: Vec<AnthropicMessage> = request
            .messages
            .iter()
            .filter(|m| m.role != Role::System)
            .map(|m| AnthropicMessage {
                role: match m.role {
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                    Role::System => "user".to_string(), // Shouldn't happen
                },
                content: m.content.clone(),
            })
            .collect();

        // Extract system message
        let system = request
            .messages
            .iter()
            .find(|m| m.role == Role::System)
            .map(|m| m.content.clone())
            .or_else(|| request.system.clone());

        let anthropic_req = AnthropicRequest {
            model: request.model.clone(),
            messages,
            max_tokens: request.max_tokens.unwrap_or(4096),
            system,
            temperature: request.temperature,
            stream: false,
        };

        let res = client
            .post(format!("{}/v1/messages", self.base_url))
            .header("x-api-key", &api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&anthropic_req)
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("Anthropic API error: {}", error_text);
        }

        let anthropic_res: AnthropicResponse = res.json().await?;

        let content = anthropic_res
            .content
            .into_iter()
            .map(|c| c.text)
            .collect::<Vec<_>>()
            .join("");

        Ok(ChatResponse {
            provider: "anthropic".to_string(),
            model: request.model.clone(),
            content,
            done: true,
            usage: Some(Usage {
                prompt_tokens: anthropic_res.usage.input_tokens,
                completion_tokens: anthropic_res.usage.output_tokens,
                total_tokens: anthropic_res.usage.input_tokens + anthropic_res.usage.output_tokens,
            }),
            finish_reason: anthropic_res.stop_reason,
        })
    }

    async fn chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>> {
        let (tx, rx) = mpsc::channel(100);

        // Convert messages
        let messages: Vec<AnthropicMessage> = request
            .messages
            .iter()
            .filter(|m| m.role != Role::System)
            .map(|m| AnthropicMessage {
                role: match m.role {
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                    Role::System => "user".to_string(),
                },
                content: m.content.clone(),
            })
            .collect();

        let system = request
            .messages
            .iter()
            .find(|m| m.role == Role::System)
            .map(|m| m.content.clone())
            .or_else(|| request.system.clone());

        let anthropic_req = AnthropicRequest {
            model: request.model.clone(),
            messages,
            max_tokens: request.max_tokens.unwrap_or(4096),
            system,
            temperature: request.temperature,
            stream: true,
        };

        let api_key = self.get_api_key().await?;
        let base_url = self.base_url.clone();
        let model = request.model.clone();

        tokio::spawn(async move {
            let client = reqwest::Client::new();

            let res = match client
                .post(format!("{}/v1/messages", base_url))
                .header("x-api-key", &api_key)
                .header("anthropic-version", "2023-06-01")
                .header("content-type", "application/json")
                .json(&anthropic_req)
                .send()
                .await
            {
                Ok(r) => r,
                Err(e) => {
                    let _ = tx.send(Err(e.into())).await;
                    return;
                }
            };

            if !res.status().is_success() {
                let error_text = res.text().await.unwrap_or_else(|_| "Unknown error".to_string());
                let _ = tx.send(Err(anyhow::anyhow!("Anthropic API error: {}", error_text))).await;
                return;
            }

            // Read SSE stream
            let mut stream = res.bytes_stream();
            use futures::StreamExt;

            let mut buffer = String::new();
            let mut input_tokens = 0;
            let mut output_tokens = 0;
            let mut finish_reason: Option<String> = None;

            while let Some(chunk) = stream.next().await {
                match chunk {
                    Ok(bytes) => {
                        buffer.push_str(&String::from_utf8_lossy(&bytes));

                        // Process complete SSE events
                        while let Some(event_end) = buffer.find("\n\n") {
                            let event_str = buffer[..event_end].to_string();
                            buffer.drain(..event_end + 2);

                            // Parse SSE event (format: "event: <type>\ndata: <json>")
                            let mut event_data: Option<String> = None;

                            for line in event_str.lines() {
                                if let Some(stripped) = line.strip_prefix("data: ") {
                                    event_data = Some(stripped.to_string());
                                }
                            }

                            // Process the event
                            if let Some(data) = event_data {
                                if let Ok(event) = serde_json::from_str::<StreamEvent>(&data) {
                                    match event {
                                        StreamEvent::MessageStart { message } => {
                                            input_tokens = message.usage.input_tokens;
                                        }
                                        StreamEvent::ContentBlockDelta { delta, .. } => {
                                            let ContentDelta::TextDelta { text } = delta;
                                            let response = ChatResponse {
                                                provider: "anthropic".to_string(),
                                                model: model.clone(),
                                                content: text,
                                                done: false,
                                                usage: None,
                                                finish_reason: None,
                                            };

                                            if tx.send(Ok(response)).await.is_err() {
                                                return;
                                            }
                                        }
                                        StreamEvent::MessageDelta { delta, usage } => {
                                            finish_reason = delta.stop_reason;
                                            if let Some(u) = usage {
                                                output_tokens = u.output_tokens;
                                            }
                                        }
                                        StreamEvent::MessageStop => {
                                            // Send final chunk with usage
                                            let response = ChatResponse {
                                                provider: "anthropic".to_string(),
                                                model: model.clone(),
                                                content: String::new(),
                                                done: true,
                                                usage: Some(Usage {
                                                    prompt_tokens: input_tokens,
                                                    completion_tokens: output_tokens,
                                                    total_tokens: input_tokens + output_tokens,
                                                }),
                                                finish_reason: finish_reason.clone(),
                                            };

                                            let _ = tx.send(Ok(response)).await;
                                            return;
                                        }
                                        _ => {} // Ignore other events
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Err(e.into())).await;
                        return;
                    }
                }
            }
        });

        Ok(rx)
    }
}

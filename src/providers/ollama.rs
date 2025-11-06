use crate::providers::Provider;
use crate::types::{ChatRequest, ChatResponse, Role};
use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

pub struct OllamaProvider {
    endpoint: String,
    model: String,
}

impl OllamaProvider {
    pub fn new(endpoint: String, model: String) -> Self {
        Self { endpoint, model }
    }

    pub fn from_config(config: &crate::config::ProviderConfig) -> Result<Self> {
        let endpoint = config.endpoint.clone()
            .unwrap_or_else(|| "http://localhost:11434".to_string());
        let model = config.model.clone()
            .unwrap_or_else(|| "codellama:latest".to_string());

        Ok(Self::new(endpoint, model))
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

// Ollama API types
#[derive(Serialize)]
struct OllamaRequest {
    model: String,
    messages: Vec<OllamaMessage>,
    stream: bool,
}

#[derive(Serialize, Deserialize)]
struct OllamaMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct OllamaResponse {
    message: OllamaMessage,
    done: bool,
}

#[async_trait]
impl Provider for OllamaProvider {
    fn name(&self) -> &str {
        "ollama"
    }

    async fn health(&self) -> Result<bool> {
        let client = reqwest::Client::new();
        let res = client
            .get(format!("{}/api/tags", self.endpoint))
            .send()
            .await;

        Ok(res.is_ok())
    }

    async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let client = reqwest::Client::new();

        let messages: Vec<OllamaMessage> = request
            .messages
            .iter()
            .map(|m| OllamaMessage {
                role: match m.role {
                    Role::System => "system".to_string(),
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                },
                content: m.content.clone(),
            })
            .collect();

        let ollama_req = OllamaRequest {
            model: request.model.clone(),
            messages,
            stream: false,
        };

        let res = client
            .post(format!("{}/api/chat", self.endpoint))
            .json(&ollama_req)
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("Ollama API error: {}", error_text);
        }

        let ollama_res: OllamaResponse = res.json().await?;

        Ok(ChatResponse {
            provider: "ollama".to_string(),
            model: request.model.clone(),
            content: ollama_res.message.content,
            done: ollama_res.done,
            usage: None, // Ollama doesn't return token usage
            finish_reason: if ollama_res.done {
                Some("stop".to_string())
            } else {
                None
            },
        })
    }

    async fn chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>> {
        let (tx, rx) = mpsc::channel(100);

        let messages: Vec<OllamaMessage> = request
            .messages
            .iter()
            .map(|m| OllamaMessage {
                role: match m.role {
                    Role::System => "system".to_string(),
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                },
                content: m.content.clone(),
            })
            .collect();

        let ollama_req = OllamaRequest {
            model: request.model.clone(),
            messages,
            stream: true,
        };

        let endpoint = self.endpoint.clone();
        let model = request.model.clone();

        tokio::spawn(async move {
            let client = reqwest::Client::new();

            let res = match client
                .post(format!("{}/api/chat", endpoint))
                .json(&ollama_req)
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
                let _ = tx.send(Err(anyhow::anyhow!("Ollama API error: {}", error_text))).await;
                return;
            }

            // Ollama streams newline-delimited JSON (not SSE)
            let mut stream = res.bytes_stream();
            use futures::StreamExt;

            let mut buffer = String::new();

            while let Some(chunk) = stream.next().await {
                match chunk {
                    Ok(bytes) => {
                        buffer.push_str(&String::from_utf8_lossy(&bytes));

                        // Process complete lines
                        while let Some(newline_pos) = buffer.find('\n') {
                            let line = buffer[..newline_pos].to_string();
                            buffer.drain(..newline_pos + 1);

                            if line.trim().is_empty() {
                                continue;
                            }

                            // Parse JSON line
                            if let Ok(ollama_chunk) = serde_json::from_str::<OllamaResponse>(&line) {
                                let response = ChatResponse {
                                    provider: "ollama".to_string(),
                                    model: model.clone(),
                                    content: ollama_chunk.message.content,
                                    done: ollama_chunk.done,
                                    usage: None,
                                    finish_reason: if ollama_chunk.done {
                                        Some("stop".to_string())
                                    } else {
                                        None
                                    },
                                };

                                if tx.send(Ok(response)).await.is_err() {
                                    return;
                                }

                                if ollama_chunk.done {
                                    return;
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

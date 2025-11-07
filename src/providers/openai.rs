use crate::providers::Provider;
use crate::types::{ChatRequest, ChatResponse, Role, Usage};
use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

pub struct OpenAIProvider {
    api_key: String,
    base_url: String,
    #[allow(dead_code)]
    model: String,
}

impl OpenAIProvider {
    pub fn new(api_key: String, model: String) -> Self {
        Self {
            api_key,
            base_url: "https://api.openai.com/v1".to_string(),
            model,
        }
    }

    pub fn from_config(config: &crate::config::ProviderConfig) -> Result<Self> {
        let api_key = config.api_key.clone()
            .ok_or_else(|| anyhow::anyhow!("OpenAI API key not configured"))?;
        let model = config.model.clone()
            .unwrap_or_else(|| "gpt-4o".to_string());

        Ok(Self::new(api_key, model))
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

// OpenAI API types
#[derive(Serialize)]
struct OpenAIRequest {
    model: String,
    messages: Vec<OpenAIMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<i32>,
    stream: bool,
}

#[derive(Serialize, Deserialize)]
struct OpenAIMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct OpenAIResponse {
    choices: Vec<Choice>,
    usage: OpenAIUsage,
}

#[derive(Deserialize)]
struct Choice {
    message: OpenAIMessage,
    finish_reason: Option<String>,
}

#[derive(Deserialize)]
struct OpenAIUsage {
    prompt_tokens: i32,
    completion_tokens: i32,
    total_tokens: i32,
}

// Streaming response types
#[derive(Deserialize, Debug)]
struct StreamChunk {
    choices: Vec<StreamChoice>,
}

#[derive(Deserialize, Debug)]
struct StreamChoice {
    delta: Delta,
    finish_reason: Option<String>,
}

#[derive(Deserialize, Debug)]
struct Delta {
    #[serde(default)]
    content: Option<String>,
}

#[async_trait]
impl Provider for OpenAIProvider {
    fn name(&self) -> &str {
        "openai"
    }

    async fn health(&self) -> Result<bool> {
        Ok(!self.api_key.is_empty())
    }

    async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let client = reqwest::Client::new();

        let messages: Vec<OpenAIMessage> = request
            .messages
            .iter()
            .map(|m| OpenAIMessage {
                role: match m.role {
                    Role::System => "system".to_string(),
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                },
                content: m.content.clone(),
            })
            .collect();

        let openai_req = OpenAIRequest {
            model: request.model.clone(),
            messages,
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: false,
        };

        let res = client
            .post(format!("{}/chat/completions", self.base_url))
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("content-type", "application/json")
            .json(&openai_req)
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("OpenAI API error: {}", error_text);
        }

        let openai_res: OpenAIResponse = res.json().await?;

        let choice = openai_res
            .choices
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("No choices in response"))?;

        Ok(ChatResponse {
            provider: "openai".to_string(),
            model: request.model.clone(),
            content: choice.message.content,
            done: true,
            usage: Some(Usage {
                prompt_tokens: openai_res.usage.prompt_tokens,
                completion_tokens: openai_res.usage.completion_tokens,
                total_tokens: openai_res.usage.total_tokens,
            }),
            finish_reason: choice.finish_reason,
        })
    }

    async fn chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>> {
        let (tx, rx) = mpsc::channel(100);

        let messages: Vec<OpenAIMessage> = request
            .messages
            .iter()
            .map(|m| OpenAIMessage {
                role: match m.role {
                    Role::System => "system".to_string(),
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                },
                content: m.content.clone(),
            })
            .collect();

        let openai_req = OpenAIRequest {
            model: request.model.clone(),
            messages,
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: true,
        };

        let api_key = self.api_key.clone();
        let base_url = self.base_url.clone();
        let model = request.model.clone();

        tokio::spawn(async move {
            let client = reqwest::Client::new();

            let res = match client
                .post(format!("{}/chat/completions", base_url))
                .header("Authorization", format!("Bearer {}", api_key))
                .header("content-type", "application/json")
                .json(&openai_req)
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
                let _ = tx.send(Err(anyhow::anyhow!("OpenAI API error: {}", error_text))).await;
                return;
            }

            // Read SSE stream
            let mut stream = res.bytes_stream();
            use futures::StreamExt;

            let mut buffer = String::new();

            while let Some(chunk) = stream.next().await {
                match chunk {
                    Ok(bytes) => {
                        buffer.push_str(&String::from_utf8_lossy(&bytes));

                        // Process complete SSE events
                        while let Some(event_end) = buffer.find("\n\n") {
                            let event_str = buffer[..event_end].to_string();
                            buffer.drain(..event_end + 2);

                            for line in event_str.lines() {
                                if let Some(data) = line.strip_prefix("data: ") {
                                    if data == "[DONE]" {
                                        return;
                                    }

                                    if let Ok(chunk) = serde_json::from_str::<StreamChunk>(data) {
                                        if let Some(choice) = chunk.choices.first() {
                                            if let Some(content) = &choice.delta.content {
                                                let response = ChatResponse {
                                                    provider: "openai".to_string(),
                                                    model: model.clone(),
                                                    content: content.clone(),
                                                    done: choice.finish_reason.is_some(),
                                                    usage: None,
                                                    finish_reason: choice.finish_reason.clone(),
                                                };

                                                if tx.send(Ok(response)).await.is_err() {
                                                    return;
                                                }
                                            }
                                        }
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

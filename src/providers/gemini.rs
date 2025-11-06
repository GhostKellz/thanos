use crate::providers::Provider;
use crate::types::{ChatRequest, ChatResponse, Role, Usage};
use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

pub struct GeminiProvider {
    api_key: String,
    base_url: String,
    model: String,
}

impl GeminiProvider {
    pub fn new(api_key: String, model: String) -> Self {
        Self {
            api_key,
            base_url: "https://generativelanguage.googleapis.com".to_string(),
            model,
        }
    }

    pub fn from_config(config: &crate::config::ProviderConfig) -> Result<Self> {
        let api_key = config.api_key.clone()
            .ok_or_else(|| anyhow::anyhow!("Gemini API key not configured"))?;
        let model = config.model.clone()
            .unwrap_or_else(|| "gemini-2.5-pro".to_string());

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

// Gemini API types
#[derive(Serialize)]
struct GeminiRequest {
    contents: Vec<GeminiContent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    system_instruction: Option<GeminiContent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    generation_config: Option<GenerationConfig>,
}

#[derive(Serialize)]
struct GeminiContent {
    parts: Vec<GeminiPart>,
    #[serde(skip_serializing_if = "Option::is_none")]
    role: Option<String>,
}

#[derive(Serialize)]
struct GeminiPart {
    text: String,
}

#[derive(Serialize)]
struct GenerationConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_output_tokens: Option<i32>,
}

#[derive(Deserialize, Debug)]
struct GeminiResponse {
    candidates: Option<Vec<GeminiCandidate>>,
    #[serde(rename = "usageMetadata")]
    usage_metadata: Option<UsageMetadata>,
    // Gemini may return an error instead
    error: Option<GeminiError>,
}

#[derive(Deserialize, Debug)]
struct GeminiError {
    code: Option<i32>,
    message: String,
    status: Option<String>,
}

#[derive(Deserialize, Debug)]
struct GeminiCandidate {
    content: GeminiContentResponse,
    #[serde(rename = "finishReason")]
    finish_reason: Option<String>,
}

#[derive(Deserialize, Debug)]
struct GeminiContentResponse {
    #[serde(default)]
    parts: Vec<GeminiPartResponse>,
    // role is always present but we don't use it
    #[serde(skip_serializing_if = "Option::is_none")]
    role: Option<String>,
}

#[derive(Deserialize, Debug)]
struct GeminiPartResponse {
    text: String,
}

#[derive(Deserialize, Debug)]
struct UsageMetadata {
    #[serde(rename = "promptTokenCount")]
    prompt_token_count: Option<i32>,
    #[serde(rename = "candidatesTokenCount")]
    candidates_token_count: Option<i32>,
    #[serde(rename = "totalTokenCount")]
    total_token_count: Option<i32>,
}

// Streaming response (Gemini uses newline-delimited JSON like Ollama)
#[derive(Deserialize, Debug)]
struct StreamResponse {
    candidates: Option<Vec<GeminiCandidate>>,
    #[serde(rename = "usageMetadata")]
    usage_metadata: Option<UsageMetadata>,
    error: Option<GeminiError>,
}

#[async_trait]
impl Provider for GeminiProvider {
    fn name(&self) -> &str {
        "gemini"
    }

    async fn health(&self) -> Result<bool> {
        // Simple health check: verify API key format
        Ok(!self.api_key.is_empty())
    }

    async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let client = reqwest::Client::new();

        // Convert messages to Gemini format
        let contents: Vec<GeminiContent> = request
            .messages
            .iter()
            .filter(|m| m.role != Role::System)
            .map(|m| GeminiContent {
                parts: vec![GeminiPart {
                    text: m.content.clone(),
                }],
                role: Some(match m.role {
                    Role::User => "user".to_string(),
                    Role::Assistant => "model".to_string(), // Gemini uses "model" instead of "assistant"
                    Role::System => "user".to_string(), // Shouldn't happen
                }),
            })
            .collect();

        // Extract system message
        let system_instruction = request
            .messages
            .iter()
            .find(|m| m.role == Role::System)
            .or_else(|| {
                request.system.as_ref().map(|_| &request.messages[0]) // Placeholder
            })
            .map(|_| GeminiContent {
                parts: vec![GeminiPart {
                    text: request
                        .system
                        .clone()
                        .or_else(|| {
                            request
                                .messages
                                .iter()
                                .find(|m| m.role == Role::System)
                                .map(|m| m.content.clone())
                        })
                        .unwrap_or_default(),
                }],
                role: None, // System instructions don't have a role
            });

        let generation_config = if request.temperature.is_some() || request.max_tokens.is_some() {
            Some(GenerationConfig {
                temperature: request.temperature,
                max_output_tokens: request.max_tokens,
            })
        } else {
            None
        };

        let gemini_req = GeminiRequest {
            contents,
            system_instruction,
            generation_config,
        };

        let url = format!(
            "{}/v1beta/models/{}:generateContent?key={}",
            self.base_url, self.model, self.api_key
        );

        let res = client
            .post(&url)
            .header("content-type", "application/json")
            .json(&gemini_req)
            .send()
            .await?;

        let status = res.status();
        let response_text = res.text().await?;

        if !status.is_success() {
            anyhow::bail!("Gemini API error ({}): {}", status, response_text);
        }

        let gemini_res: GeminiResponse = serde_json::from_str(&response_text)
            .map_err(|e| anyhow::anyhow!("Failed to parse Gemini response: {}. Response: {}", e, response_text))?;

        // Check for API error in response
        if let Some(error) = gemini_res.error {
            anyhow::bail!(
                "Gemini API error {}: {} (status: {})",
                error.code.unwrap_or(0),
                error.message,
                error.status.unwrap_or_else(|| "UNKNOWN".to_string())
            );
        }

        // Extract content from candidates
        let content = gemini_res
            .candidates
            .as_ref()
            .and_then(|candidates| candidates.first())
            .map(|c| {
                c.content
                    .parts
                    .iter()
                    .map(|p| p.text.clone())
                    .collect::<Vec<_>>()
                    .join("")
            })
            .unwrap_or_default();

        let usage = gemini_res.usage_metadata.map(|u| Usage {
            prompt_tokens: u.prompt_token_count.unwrap_or(0),
            completion_tokens: u.candidates_token_count.unwrap_or(0),
            total_tokens: u.total_token_count.unwrap_or(0),
        });

        let finish_reason = gemini_res
            .candidates
            .as_ref()
            .and_then(|candidates| candidates.first())
            .and_then(|c| c.finish_reason.clone());

        Ok(ChatResponse {
            provider: "gemini".to_string(),
            model: request.model.clone(),
            content,
            done: true,
            usage,
            finish_reason,
        })
    }

    async fn chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>> {
        let (tx, rx) = mpsc::channel(100);

        // Convert messages to Gemini format
        let contents: Vec<GeminiContent> = request
            .messages
            .iter()
            .filter(|m| m.role != Role::System)
            .map(|m| GeminiContent {
                parts: vec![GeminiPart {
                    text: m.content.clone(),
                }],
                role: Some(match m.role {
                    Role::User => "user".to_string(),
                    Role::Assistant => "model".to_string(),
                    Role::System => "user".to_string(),
                }),
            })
            .collect();

        // Extract system message
        let system_instruction = request
            .messages
            .iter()
            .find(|m| m.role == Role::System)
            .or_else(|| {
                request.system.as_ref().map(|_| &request.messages[0])
            })
            .map(|_| GeminiContent {
                parts: vec![GeminiPart {
                    text: request
                        .system
                        .clone()
                        .or_else(|| {
                            request
                                .messages
                                .iter()
                                .find(|m| m.role == Role::System)
                                .map(|m| m.content.clone())
                        })
                        .unwrap_or_default(),
                }],
                role: None,
            });

        let generation_config = if request.temperature.is_some() || request.max_tokens.is_some() {
            Some(GenerationConfig {
                temperature: request.temperature,
                max_output_tokens: request.max_tokens,
            })
        } else {
            None
        };

        let gemini_req = GeminiRequest {
            contents,
            system_instruction,
            generation_config,
        };

        let api_key = self.api_key.clone();
        let base_url = self.base_url.clone();
        let model_name = self.model.clone();
        let request_model = request.model.clone();

        tokio::spawn(async move {
            let client = reqwest::Client::new();

            let url = format!(
                "{}/v1beta/models/{}:streamGenerateContent?key={}",
                base_url, model_name, api_key
            );

            let res = match client
                .post(&url)
                .header("content-type", "application/json")
                .json(&gemini_req)
                .send()
                .await
            {
                Ok(r) => r,
                Err(e) => {
                    let _ = tx.send(Err(e.into())).await;
                    return;
                }
            };

            let status = res.status();
            if !status.is_success() {
                let error_text = res.text().await.unwrap_or_else(|_| "Unknown error".to_string());
                let _ = tx.send(Err(anyhow::anyhow!("Gemini API error ({}): {}", status, error_text))).await;
                return;
            }

            // Gemini streams newline-delimited JSON
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
                            match serde_json::from_str::<StreamResponse>(&line) {
                                Ok(stream_res) => {
                                    // Check for error in response
                                    if let Some(error) = stream_res.error {
                                        let err_msg = format!(
                                            "Gemini API error {}: {} (status: {})",
                                            error.code.unwrap_or(0),
                                            error.message,
                                            error.status.unwrap_or_else(|| "UNKNOWN".to_string())
                                        );
                                        let _ = tx.send(Err(anyhow::anyhow!(err_msg))).await;
                                        return;
                                    }

                                    // Process candidates
                                    if let Some(candidates) = stream_res.candidates.as_ref() {
                                        if let Some(candidate) = candidates.first() {
                                            let content = candidate
                                                .content
                                                .parts
                                                .iter()
                                                .map(|p| p.text.clone())
                                                .collect::<Vec<_>>()
                                                .join("");

                                            if !content.is_empty() {
                                                let response = ChatResponse {
                                                    provider: "gemini".to_string(),
                                                    model: request_model.clone(),
                                                    content,
                                                    done: candidate.finish_reason.is_some(),
                                                    usage: stream_res.usage_metadata.as_ref().map(|u| Usage {
                                                        prompt_tokens: u.prompt_token_count.unwrap_or(0),
                                                        completion_tokens: u.candidates_token_count.unwrap_or(0),
                                                        total_tokens: u.total_token_count.unwrap_or(0),
                                                    }),
                                                    finish_reason: candidate.finish_reason.clone(),
                                                };

                                                if tx.send(Ok(response)).await.is_err() {
                                                    return;
                                                }
                                            }
                                        }
                                    }
                                }
                                Err(e) => {
                                    tracing::warn!("Failed to parse Gemini stream line: {}. Line: {}", e, line);
                                    // Don't return on parse errors, just log and continue
                                    continue;
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

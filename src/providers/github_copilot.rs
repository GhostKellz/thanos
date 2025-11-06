use crate::providers::Provider;
use crate::types::{ChatRequest, ChatResponse, Role, Usage};
use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

pub struct GitHubCopilotProvider {
    model: String,
}

impl GitHubCopilotProvider {
    pub fn new(model: String) -> Self {
        Self { model }
    }

    pub fn from_config(config: &crate::config::ProviderConfig) -> Result<Self> {
        let model = config
            .model
            .clone()
            .unwrap_or_else(|| "gpt-4".to_string());

        Ok(Self::new(model))
    }

    async fn get_copilot_token(&self) -> Result<String> {
        let token_manager = crate::auth::TokenManager::new();
        token_manager.get_access_token("github_copilot").await
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

// GitHub Copilot uses OpenAI-compatible API
#[derive(Serialize)]
struct CopilotRequest {
    model: String,
    messages: Vec<CopilotMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<i32>,
    stream: bool,
}

#[derive(Serialize, Deserialize)]
struct CopilotMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct CopilotResponse {
    choices: Vec<CopilotChoice>,
    usage: CopilotUsage,
}

#[derive(Deserialize)]
struct CopilotChoice {
    message: CopilotMessage,
    finish_reason: Option<String>,
}

#[derive(Deserialize)]
struct CopilotUsage {
    prompt_tokens: i32,
    completion_tokens: i32,
    total_tokens: i32,
}

#[async_trait]
impl Provider for GitHubCopilotProvider {
    fn name(&self) -> &str {
        "github_copilot"
    }

    async fn health(&self) -> Result<bool> {
        Ok(self.get_copilot_token().await.is_ok())
    }

    async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let token = self.get_copilot_token().await?;
        let client = reqwest::Client::new();

        let messages: Vec<CopilotMessage> = request
            .messages
            .iter()
            .map(|m| CopilotMessage {
                role: match m.role {
                    Role::System => "system".to_string(),
                    Role::User => "user".to_string(),
                    Role::Assistant => "assistant".to_string(),
                },
                content: m.content.clone(),
            })
            .collect();

        let copilot_req = CopilotRequest {
            model: request.model.clone(),
            messages,
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: false,
        };

        // GitHub Copilot endpoint
        let res = client
            .post("https://api.githubcopilot.com/chat/completions")
            .header("Authorization", format!("Bearer {}", token))
            .header("Content-Type", "application/json")
            .header("Editor-Version", "vscode/1.85.0")
            .header("Editor-Plugin-Version", "copilot-chat/0.11.1")
            .json(&copilot_req)
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("GitHub Copilot API error: {}", error_text);
        }

        let copilot_res: CopilotResponse = res.json().await?;

        let choice = copilot_res
            .choices
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("No choices in response"))?;

        Ok(ChatResponse {
            provider: "github_copilot".to_string(),
            model: request.model.clone(),
            content: choice.message.content,
            done: true,
            usage: Some(Usage {
                prompt_tokens: copilot_res.usage.prompt_tokens,
                completion_tokens: copilot_res.usage.completion_tokens,
                total_tokens: copilot_res.usage.total_tokens,
            }),
            finish_reason: choice.finish_reason,
        })
    }

    async fn chat_completion_stream(
        &self,
        _request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>> {
        // TODO: Implement streaming for GitHub Copilot
        anyhow::bail!("Streaming not yet implemented for GitHub Copilot")
    }
}

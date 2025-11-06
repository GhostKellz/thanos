pub mod anthropic;
pub mod gemini;
pub mod github_copilot;
pub mod ollama;
pub mod openai;
pub mod xai;

use crate::types::{ChatRequest, ChatResponse};
use anyhow::Result;
use async_trait::async_trait;
use tokio::sync::mpsc;

/// Provider trait for AI model inference
#[async_trait]
pub trait Provider: Send + Sync {
    /// Provider name
    fn name(&self) -> &str;

    /// Check if provider is healthy
    async fn health(&self) -> Result<bool>;

    /// Chat completion (non-streaming)
    async fn chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse>;

    /// Chat completion (streaming) - returns a receiver for streaming responses
    async fn chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<mpsc::Receiver<Result<ChatResponse>>>;
}

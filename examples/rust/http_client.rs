/// Example: HTTP client for Thanos (OpenAI-compatible API)
///
/// This shows how to call Thanos via HTTP/REST instead of gRPC.
/// Useful for web clients, curl, or when gRPC isn't available.
///
/// Usage:
///   cargo build --example http_client
///   ./target/debug/examples/http_client

use anyhow::Result;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<i32>,
}

#[derive(Serialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Deserialize, Debug)]
struct ChatResponse {
    provider: String,
    model: String,
    content: String,
    done: bool,
    usage: Option<Usage>,
    finish_reason: Option<String>,
}

#[derive(Deserialize, Debug)]
struct Usage {
    prompt_tokens: i32,
    completion_tokens: i32,
    total_tokens: i32,
}

#[tokio::main]
async fn main() -> Result<()> {
    let client = reqwest::Client::new();

    let request = ChatRequest {
        model: "anthropic/claude-3-5-sonnet-20241022".to_string(),
        messages: vec![Message {
            role: "user".to_string(),
            content: "What is the difference between Arc and Rc in Rust?".to_string(),
        }],
        stream: Some(false),
        temperature: Some(0.7),
        max_tokens: Some(1024),
    };

    println!("🌐 HTTP request to Thanos...\n");

    let response = client
        .post("http://localhost:8080/v1/chat/completions")
        .json(&request)
        .send()
        .await?;

    if !response.status().is_success() {
        anyhow::bail!("HTTP error: {}", response.status());
    }

    let chat_response: ChatResponse = response.json().await?;

    println!("{}\n", chat_response.content);

    if let Some(usage) = chat_response.usage {
        println!("📊 Token usage:");
        println!("   Prompt: {}", usage.prompt_tokens);
        println!("   Completion: {}", usage.completion_tokens);
        println!("   Total: {}", usage.total_tokens);
    }

    println!("✅ Provider: {}", chat_response.provider);
    println!("🤖 Model: {}", chat_response.model);

    Ok(())
}

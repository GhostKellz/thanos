/// Example: Basic gRPC client for Thanos
///
/// This shows how zeke (or any Rust client) can call Thanos via gRPC.
///
/// Usage:
///   cargo build --example grpc_client
///   ./target/debug/examples/grpc_client

use anyhow::Result;

// You'll use the generated proto types from your build
// In zeke, you'd include thanos proto in your build.rs
mod thanos {
    tonic::include_proto!("thanos");
}

use thanos::thanos_service_client::ThanosServiceClient;
use thanos::{ChatRequest, Message};

#[tokio::main]
async fn main() -> Result<()> {
    // Connect to Thanos gRPC server
    let mut client = ThanosServiceClient::connect("http://localhost:50051").await?;

    // Build request
    let request = tonic::Request::new(ChatRequest {
        model: "claude-3-5-sonnet-20241022".to_string(),
        messages: vec![Message {
            role: "user".to_string(),
            content: "Write a quicksort in Rust".to_string(),
        }],
        stream: false,
        temperature: Some(0.7),
        max_tokens: Some(2048),
        top_p: None,
        system: None,
    });

    println!("📡 Sending request to Thanos...\n");

    // Call ChatCompletion
    let mut stream = client.chat_completion(request).await?.into_inner();

    // Handle response stream
    while let Some(response) = stream.message().await? {
        print!("{}", response.content);
        std::io::Write::flush(&mut std::io::stdout())?;

        if response.done {
            println!("\n");
            if let Some(usage) = response.usage {
                println!("📊 Token usage:");
                println!("   Prompt: {}", usage.prompt_tokens);
                println!("   Completion: {}", usage.completion_tokens);
                println!("   Total: {}", usage.total_tokens);
            }
            println!("✅ Provider: {}", response.provider);
            println!("🤖 Model: {}", response.model);
        }
    }

    Ok(())
}

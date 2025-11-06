/// Example: Streaming gRPC client for Thanos
///
/// This shows how to handle streaming responses from Thanos.
/// Perfect for real-time code generation in editors.
///
/// Usage:
///   cargo build --example grpc_streaming
///   ./target/debug/examples/grpc_streaming

use anyhow::Result;

mod thanos {
    tonic::include_proto!("thanos");
}

use thanos::thanos_service_client::ThanosServiceClient;
use thanos::{ChatRequest, Message};

#[tokio::main]
async fn main() -> Result<()> {
    let mut client = ThanosServiceClient::connect("http://localhost:50051").await?;

    let request = tonic::Request::new(ChatRequest {
        model: "auto".to_string(), // Let Thanos pick best provider
        messages: vec![Message {
            role: "user".to_string(),
            content: "Explain Rust async/await in 3 sentences".to_string(),
        }],
        stream: true, // ⚡ Enable streaming
        temperature: Some(0.8),
        max_tokens: Some(500),
        top_p: None,
        system: Some("You are a concise Rust expert.".to_string()),
    });

    println!("⚡ Streaming response from Thanos...\n");

    let mut stream = client.chat_completion(request).await?.into_inner();
    let mut total_tokens = 0;

    // Stream tokens as they arrive
    while let Some(chunk) = stream.message().await? {
        if !chunk.content.is_empty() {
            print!("{}", chunk.content);
            std::io::Write::flush(&mut std::io::stdout())?;
        }

        if chunk.done {
            println!("\n");
            if let Some(usage) = chunk.usage {
                total_tokens = usage.total_tokens;
                println!("📊 {} tokens used", total_tokens);
            }
            println!("✅ Provider: {}", chunk.provider);
            if let Some(reason) = chunk.finish_reason {
                println!("🏁 Finish reason: {}", reason);
            }
        }
    }

    Ok(())
}

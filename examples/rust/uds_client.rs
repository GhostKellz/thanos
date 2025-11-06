/// Example: Unix Domain Socket client for Thanos
///
/// This shows the FASTEST way to call Thanos from local clients (zeke, nvim).
/// UDS is 2-3x faster than TCP for local IPC.
///
/// Usage:
///   cargo build --example uds_client
///   ./target/debug/examples/uds_client

use anyhow::Result;
use hyper::body::Bytes;
use hyper::{Method, Request};
use hyper_util::client::legacy::Client;
use hyper_util::rt::TokioExecutor;
use hyperlocal::{UnixClientExt, Uri};
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    stream: bool,
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
}

#[tokio::main]
async fn main() -> Result<()> {
    // Connect via Unix socket
    let socket_path = "/var/run/thanos/thanos.sock";

    let url = Uri::new(socket_path, "/v1/chat/completions");

    let client = Client::unix();

    let request_body = ChatRequest {
        model: "auto".to_string(),
        messages: vec![Message {
            role: "user".to_string(),
            content: "Hello from Unix socket!".to_string(),
        }],
        stream: false,
    };

    let body_bytes = serde_json::to_vec(&request_body)?;

    let req = Request::builder()
        .method(Method::POST)
        .uri(url)
        .header("content-type", "application/json")
        .body(body_bytes.into())?;

    println!("🔌 UDS request to Thanos at {}...\n", socket_path);

    let response = client.request(req).await?;

    if !response.status().is_success() {
        anyhow::bail!("HTTP error: {}", response.status());
    }

    let body_bytes = hyper::body::to_bytes(response.into_body()).await?;
    let chat_response: ChatResponse = serde_json::from_slice(&body_bytes)?;

    println!("{}\n", chat_response.content);
    println!("✅ Provider: {}", chat_response.provider);
    println!("🤖 Model: {}", chat_response.model);
    println!("⚡ via Unix Domain Socket (fastest!)");

    Ok(())
}

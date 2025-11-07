use anyhow::Result;
use reqwest::Client;
use serde_json::json;
use std::time::Duration;
use tokio::time::sleep;

/// Test helper to check if Thanos server is running
async fn is_server_running() -> bool {
    let client = Client::new();
    client
        .get("http://localhost:8080/health")
        .timeout(Duration::from_secs(1))
        .send()
        .await
        .is_ok()
}

#[tokio::test]
async fn test_health_endpoint() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    let client = Client::new();
    let response = client.get("http://localhost:8080/health").send().await?;

    assert_eq!(response.status(), 200);
    let body: serde_json::Value = response.json().await?;
    assert_eq!(body["status"], "ok");

    Ok(())
}

#[tokio::test]
async fn test_models_endpoint() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    let client = Client::new();
    let response = client.get("http://localhost:8080/v1/models").send().await?;

    assert_eq!(response.status(), 200);
    let body: serde_json::Value = response.json().await?;
    assert!(body.get("data").is_some());

    Ok(())
}

#[tokio::test]
async fn test_chat_completion_basic() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    let client = Client::new();
    let payload = json!({
        "messages": [
            {
                "role": "user",
                "content": "Say hello in exactly 2 words"
            }
        ],
        "stream": false
    });

    let response = client
        .post("http://localhost:8080/v1/chat/completions")
        .json(&payload)
        .send()
        .await?;

    assert_eq!(response.status(), 200);
    let body: serde_json::Value = response.json().await?;

    // Check response structure
    assert!(body.get("choices").is_some());
    assert!(body["choices"].is_array());
    assert!(!body["choices"].as_array().unwrap().is_empty());

    let message = &body["choices"][0]["message"];
    assert_eq!(message["role"], "assistant");
    assert!(message["content"].is_string());

    Ok(())
}

#[tokio::test]
async fn test_streaming_response() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    let client = Client::new();
    let payload = json!({
        "messages": [
            {
                "role": "user",
                "content": "Count from 1 to 3"
            }
        ],
        "stream": true
    });

    let response = client
        .post("http://localhost:8080/v1/chat/completions")
        .json(&payload)
        .send()
        .await?;

    assert_eq!(response.status(), 200);
    assert_eq!(
        response.headers().get("content-type").unwrap(),
        "text/event-stream"
    );

    Ok(())
}

#[tokio::test]
async fn test_rate_limiting() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    let client = Client::new();
    let payload = json!({
        "messages": [
            {
                "role": "user",
                "content": "Hi"
            }
        ],
        "stream": false
    });

    // Make multiple rapid requests
    for i in 0..3 {
        let response = client
            .post("http://localhost:8080/v1/chat/completions")
            .json(&payload)
            .timeout(Duration::from_secs(10))
            .send()
            .await?;

        println!("Request {}: status {}", i + 1, response.status());

        // Should succeed or rate limit, but not error
        assert!(response.status().is_success() || response.status().as_u16() == 429);

        sleep(Duration::from_millis(500)).await;
    }

    Ok(())
}

#[tokio::test]
async fn test_invalid_request() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    let client = Client::new();
    let payload = json!({
        "messages": [] // Empty messages should fail
    });

    let response = client
        .post("http://localhost:8080/v1/chat/completions")
        .json(&payload)
        .send()
        .await?;

    // Should return 4xx error
    assert!(response.status().is_client_error());

    Ok(())
}

#[tokio::test]
async fn test_provider_fallback() -> Result<()> {
    if !is_server_running().await {
        eprintln!("Skipping test: Thanos server not running");
        return Ok(());
    }

    // Test that requests work even if primary provider fails
    // This assumes fallback chain is configured
    let client = Client::new();
    let payload = json!({
        "messages": [
            {
                "role": "user",
                "content": "Test"
            }
        ],
        "stream": false
    });

    let response = client
        .post("http://localhost:8080/v1/chat/completions")
        .json(&payload)
        .timeout(Duration::from_secs(15))
        .send()
        .await?;

    // Should succeed via some provider
    assert!(response.status().is_success());

    Ok(())
}

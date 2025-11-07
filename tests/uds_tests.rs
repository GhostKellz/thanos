// UDS (Unix Domain Socket) integration tests
// These tests require a running Thanos server with UDS enabled

use hyper::StatusCode;
use hyper_util::rt::TokioIo;
use serde_json::json;
use std::path::PathBuf;
use tokio::net::UnixStream;

/// Test UDS connection and health check
#[tokio::test]
async fn test_uds_health_check() {
    let socket_path = "/tmp/thanos.sock";

    // Check if socket exists
    if !PathBuf::from(socket_path).exists() {
        eprintln!("Skipping test: UDS socket not found at {}", socket_path);
        return;
    }

    // Connect to Unix socket
    let stream = match UnixStream::connect(socket_path).await {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to connect to UDS: {}", e);
            return;
        }
    };

    let io = TokioIo::new(stream);

    // Create HTTP/1.1 connection over Unix socket
    let (mut sender, conn) = match hyper::client::conn::http1::handshake(io).await {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to handshake: {}", e);
            return;
        }
    };

    // Spawn connection handler
    tokio::spawn(async move {
        if let Err(e) = conn.await {
            eprintln!("Connection error: {}", e);
        }
    });

    // Test health endpoint
    let req = hyper::Request::builder()
        .uri("/health")
        .method("GET")
        .body(String::new())
        .unwrap();

    let response = match sender.send_request(req).await {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Request failed: {}", e);
            return;
        }
    };

    assert_eq!(response.status(), StatusCode::OK);
    println!("✓ UDS health check passed");
}

#[tokio::test]
async fn test_uds_models_endpoint() {
    let socket_path = "/tmp/thanos.sock";

    if !PathBuf::from(socket_path).exists() {
        eprintln!("Skipping test: UDS socket not found");
        return;
    }

    let stream = match UnixStream::connect(socket_path).await {
        Ok(s) => s,
        Err(_) => return,
    };

    let io = TokioIo::new(stream);
    let (mut sender, conn) = match hyper::client::conn::http1::handshake(io).await {
        Ok(c) => c,
        Err(_) => return,
    };

    tokio::spawn(async move {
        let _ = conn.await;
    });

    let req = hyper::Request::builder()
        .uri("/v1/models")
        .method("GET")
        .body(String::new())
        .unwrap();

    let response = match sender.send_request(req).await {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Request failed: {}", e);
            return;
        }
    };

    assert_eq!(response.status(), StatusCode::OK);
    println!("✓ UDS models endpoint passed");
}

#[tokio::test]
async fn test_uds_reconnection() {
    let socket_path = "/tmp/thanos.sock";

    if !PathBuf::from(socket_path).exists() {
        eprintln!("Skipping test: UDS socket not found");
        return;
    }

    // Make multiple connections to test reconnection handling
    for i in 0..3 {
        let stream = match UnixStream::connect(socket_path).await {
            Ok(s) => s,
            Err(e) => {
                eprintln!("Connection {} failed: {}", i + 1, e);
                continue;
            }
        };

        let io = TokioIo::new(stream);
        let (mut sender, conn) = match hyper::client::conn::http1::handshake(io).await {
            Ok(c) => c,
            Err(_) => continue,
        };

        tokio::spawn(async move {
            let _ = conn.await;
        });

        let req = hyper::Request::builder()
            .uri("/health")
            .method("GET")
            .body(String::new())
            .unwrap();

        match sender.send_request(req).await {
            Ok(response) => {
                assert_eq!(response.status(), StatusCode::OK);
                println!("✓ Connection {} succeeded", i + 1);
            }
            Err(e) => {
                eprintln!("✗ Connection {} failed: {}", i + 1, e);
            }
        }

        // Small delay between connections
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }

    println!("✓ UDS reconnection test completed");
}

#[tokio::test]
async fn test_uds_concurrent_requests() {
    let socket_path = "/tmp/thanos.sock";

    if !PathBuf::from(socket_path).exists() {
        eprintln!("Skipping test: UDS socket not found");
        return;
    }

    // Spawn multiple concurrent requests
    let mut handles = vec![];

    for _i in 0..5 {
        let path = socket_path.to_string();
        let handle = tokio::spawn(async move {
            let stream = UnixStream::connect(&path).await.ok()?;
            let io = TokioIo::new(stream);
            let (mut sender, conn) = hyper::client::conn::http1::handshake(io).await.ok()?;

            tokio::spawn(async move {
                let _ = conn.await;
            });

            let req = hyper::Request::builder()
                .uri("/health")
                .method("GET")
                .body(String::new())
                .ok()?;

            let response = sender.send_request(req).await.ok()?;
            Some(response.status() == StatusCode::OK)
        });

        handles.push(handle);
    }

    // Wait for all requests
    let mut success_count = 0;
    for (i, handle) in handles.into_iter().enumerate() {
        match handle.await {
            Ok(Some(true)) => {
                success_count += 1;
                println!("✓ Concurrent request {} succeeded", i + 1);
            }
            _ => println!("✗ Concurrent request {} failed", i + 1),
        }
    }

    assert!(success_count >= 3, "Most concurrent requests should succeed");
    println!("✓ UDS concurrent requests test passed ({}/5)", success_count);
}

#[tokio::test]
async fn test_uds_socket_permissions() {
    let socket_path = "/tmp/thanos.sock";

    if !PathBuf::from(socket_path).exists() {
        eprintln!("Skipping test: UDS socket not found");
        return;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        match std::fs::metadata(socket_path) {
            Ok(metadata) => {
                let permissions = metadata.permissions();
                let mode = permissions.mode();

                println!("Socket permissions: {:o}", mode & 0o777);

                // Socket should not be world-readable/writable
                assert_eq!(mode & 0o007, 0, "Socket should not have world permissions");

                println!("✓ UDS permissions test passed");
            }
            Err(e) => {
                eprintln!("Failed to get socket metadata: {}", e);
            }
        }
    }

    #[cfg(not(unix))]
    {
        eprintln!("Skipping permissions test on non-Unix platform");
    }
}

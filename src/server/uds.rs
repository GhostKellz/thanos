use crate::config::Config;
use anyhow::{Context, Result};
use axum::Router;
use hyper::body::Incoming;
use hyper::Request;
use hyper_util::rt::TokioIo;
use hyper_util::server::conn::auto::Builder;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::UnixListener;
use tokio::signal;
use tokio::time::timeout;
use tower::Service;
use tracing::{debug, error, info, warn};

use super::http::AppState;

/// Start Unix Domain Socket server with graceful shutdown and connection tracking
pub async fn serve(config: Config, app: Router) -> Result<()> {
    let socket_path = config
        .server
        .uds_path
        .clone()
        .unwrap_or_else(|| "/var/run/thanos/thanos.sock".to_string());

    // Remove existing socket if it exists (handles stale sockets from crashes)
    if Path::new(&socket_path).exists() {
        warn!("Removing existing socket at {}", socket_path);
        std::fs::remove_file(&socket_path)
            .context("Failed to remove existing socket")?;
    }

    // Create parent directory if needed
    if let Some(parent) = Path::new(&socket_path).parent() {
        std::fs::create_dir_all(parent)
            .context("Failed to create socket directory")?;
    }

    let listener = UnixListener::bind(&socket_path)
        .context(format!("Failed to bind to socket at {}", socket_path))?;

    // Set socket permissions to 0600 (owner read/write only)
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let permissions = std::fs::Permissions::from_mode(0o600);
        std::fs::set_permissions(&socket_path, permissions)
            .context("Failed to set socket permissions")?;
    }

    // Track active connections for graceful shutdown
    let active_connections = Arc::new(AtomicUsize::new(0));
    let active_conn_counter = active_connections.clone();

    info!("✓ UDS server listening on {}", socket_path);

    // Set up graceful shutdown handler
    let socket_path_clone = socket_path.clone();
    tokio::spawn(async move {
        shutdown_signal().await;
        info!("Received shutdown signal, cleaning up UDS socket...");

        // Wait for active connections to finish (max 10 seconds)
        let start = std::time::Instant::now();
        while active_conn_counter.load(Ordering::Relaxed) > 0
            && start.elapsed() < Duration::from_secs(10)
        {
            debug!(
                "Waiting for {} active connections to finish...",
                active_conn_counter.load(Ordering::Relaxed)
            );
            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        // Clean up socket file
        if Path::new(&socket_path_clone).exists() {
            if let Err(e) = std::fs::remove_file(&socket_path_clone) {
                error!("Failed to remove socket on shutdown: {}", e);
            } else {
                info!("✓ Cleaned up socket at {}", socket_path_clone);
            }
        }
    });

    // Main accept loop
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => {
                active_connections.fetch_add(1, Ordering::Relaxed);
                debug!(
                    "New UDS connection (active: {})",
                    active_connections.load(Ordering::Relaxed)
                );
                conn
            }
            Err(e) => {
                error!("Failed to accept UDS connection: {}", e);
                // Back off on repeated errors
                tokio::time::sleep(Duration::from_millis(100)).await;
                continue;
            }
        };

        let io = TokioIo::new(stream);
        let app = app.clone();
        let conn_counter = active_connections.clone();

        tokio::spawn(async move {
            let service = hyper::service::service_fn(move |req: Request<Incoming>| {
                let mut app = app.clone();
                async move { app.call(req).await }
            });

            // Create builder with graceful shutdown support
            let builder = Builder::new(hyper_util::rt::TokioExecutor::new());

            // Wrap connection with timeout to prevent hanging connections
            let conn_timeout = timeout(
                Duration::from_secs(300), // 5 minute timeout per connection
                builder.serve_connection(io, service)
            );

            match conn_timeout.await {
                Ok(Ok(())) => {
                    debug!("UDS connection closed gracefully");
                }
                Ok(Err(e)) => {
                    // Only log if it's not a graceful disconnect
                    if !e.to_string().contains("connection closed") {
                        warn!("Error serving UDS connection: {}", e);
                    }
                }
                Err(_) => {
                    warn!("UDS connection timed out after 5 minutes");
                }
            }

            // Decrement active connection counter
            let remaining = conn_counter.fetch_sub(1, Ordering::Relaxed) - 1;
            debug!("UDS connection ended (active: {})", remaining);
        });
    }
}

/// Wait for shutdown signal (SIGTERM or SIGINT)
async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {
            info!("Received Ctrl+C");
        }
        _ = terminate => {
            info!("Received SIGTERM");
        }
    }
}

/// Build the router for UDS (same as HTTP)
pub fn build_router(state: AppState) -> Router {
    use super::http::{chat_completions_handler, health_handler, models_handler};
    use axum::routing::{get, post};
    use tower_http::{compression::CompressionLayer, trace::TraceLayer};

    Router::new()
        .route("/health", get(health_handler))
        .route("/v1/models", get(models_handler))
        .route("/v1/chat/completions", post(chat_completions_handler))
        .layer(TraceLayer::new_for_http())
        .layer(CompressionLayer::new())
        .with_state(state)
}

use crate::config::Config;
use anyhow::Result;
use axum::Router;
use hyper::body::Incoming;
use hyper::Request;
use hyper_util::rt::TokioIo;
use hyper_util::server::conn::auto::Builder;
use std::path::Path;
use tokio::net::UnixListener;
use tower::Service;
use tracing::{error, info};

use super::http::AppState;

/// Start Unix Domain Socket server
pub async fn serve(config: Config, app: Router) -> Result<()> {
    let socket_path = config
        .server
        .uds_path
        .clone()
        .unwrap_or_else(|| "/var/run/thanos/thanos.sock".to_string());

    // Remove existing socket if it exists
    if Path::new(&socket_path).exists() {
        std::fs::remove_file(&socket_path)?;
    }

    // Create parent directory if needed
    if let Some(parent) = Path::new(&socket_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    let listener = UnixListener::bind(&socket_path)?;

    // Set socket permissions to 0600 (owner read/write only)
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let permissions = std::fs::Permissions::from_mode(0o600);
        std::fs::set_permissions(&socket_path, permissions)?;
    }

    info!("✓ UDS server listening on {}", socket_path);

    loop {
        let (stream, _) = match listener.accept().await {
            Ok(conn) => conn,
            Err(e) => {
                error!("Failed to accept UDS connection: {}", e);
                continue;
            }
        };

        let io = TokioIo::new(stream);
        let app = app.clone();

        tokio::spawn(async move {
            let service = hyper::service::service_fn(move |req: Request<Incoming>| {
                let mut app = app.clone();
                async move { app.call(req).await }
            });

            // Create builder per connection
            let builder = Builder::new(hyper_util::rt::TokioExecutor::new());
            if let Err(e) = builder.serve_connection(io, service).await {
                error!("Error serving UDS connection: {}", e);
            }
        });
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

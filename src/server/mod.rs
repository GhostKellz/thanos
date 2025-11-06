pub mod grpc;
pub mod http;
pub mod http3;
pub mod uds;

use crate::config::Config;
use anyhow::Result;
use std::sync::Arc;
use tracing::info;

/// Run HTTP, gRPC, and UDS servers concurrently
pub async fn run(config: Config) -> Result<()> {
    let http_addr = config.server.bind.clone();
    let grpc_addr = config.server.grpc.clone();
    let uds_enabled = config.server.uds_enabled;

    // Clone config for all servers
    let http_config = config.clone();
    let grpc_config = config.clone();
    let uds_config = config;

    // Spawn HTTP server
    let http_handle = tokio::spawn(async move {
        info!("🌐 HTTP server starting on {}", http_addr);
        http::serve(http_config).await
    });

    // Spawn gRPC server
    let grpc_handle = tokio::spawn(async move {
        info!("⚡ gRPC server starting on {}", grpc_addr);
        grpc::serve(grpc_config).await
    });

    // Spawn UDS server (optional)
    let uds_handle = if uds_enabled {
        let socket_path = uds_config
            .server
            .uds_path
            .clone()
            .unwrap_or_else(|| "/var/run/thanos/thanos.sock".to_string());

        Some(tokio::spawn(async move {
            info!("🔌 UDS server starting on {}", socket_path);

            // Build shared app with router
            let config_arc = Arc::new(uds_config.clone());
            let router = Arc::new(crate::router::Router::new(config_arc.clone()));

            let state = http::AppState {
                config: config_arc,
                router,
            };
            let app = uds::build_router(state);

            uds::serve(uds_config, app).await
        }))
    } else {
        None
    };

    // Wait for all servers (any one crashing will terminate)
    if let Some(uds_handle) = uds_handle {
        tokio::select! {
            res = http_handle => {
                res??;
            }
            res = grpc_handle => {
                res??;
            }
            res = uds_handle => {
                res??;
            }
        }
    } else {
        tokio::select! {
            res = http_handle => {
                res??;
            }
            res = grpc_handle => {
                res??;
            }
        }
    }

    Ok(())
}

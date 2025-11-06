use anyhow::Result;
use thanos::{auth::{AnthropicOAuth, GitHubOAuth, KeyringStore, OAuthTokens}, config::Config, server};
use tracing::info;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    // Check for subcommands
    if args.len() >= 2 && args[1] == "auth" {
        // Handle auth subcommand
        if args.len() < 3 {
            eprintln!("Usage: thanos auth <claude|copilot|status|clear>");
            std::process::exit(1);
        }

        let keyring = KeyringStore::new("thanos");

        match args[2].as_str() {
            "claude" => {
                let oauth = AnthropicOAuth::new();
                let token_response = oauth.authorize().await?;

                let expires_at = chrono::Utc::now().timestamp() + token_response.expires_in as i64;

                let tokens = OAuthTokens {
                    access_token: token_response.access_token,
                    refresh_token: Some(token_response.refresh_token),
                    expires_at: Some(expires_at),
                };

                keyring.store_oauth_tokens("anthropic_max", &tokens)?;

                println!("🔒 Tokens stored securely in system keyring");
                println!("⏰ Expires: {}\n", chrono::DateTime::from_timestamp(expires_at, 0).unwrap());
            }

            "copilot" | "github" => {
                let oauth = GitHubOAuth::new();
                let (github_token, copilot_token, expires_at) = oauth.authorize().await?;

                let tokens = OAuthTokens {
                    access_token: copilot_token,
                    refresh_token: Some(github_token),
                    expires_at: Some(expires_at),
                };

                keyring.store_oauth_tokens("github_copilot", &tokens)?;

                println!("🔒 Tokens stored securely in system keyring");
                println!("⏰ Expires: {}\n", chrono::DateTime::from_timestamp(expires_at, 0).unwrap());
            }

            "status" => {
                println!("\n🔐 Authentication Status");
                println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

                let providers = vec![
                    ("anthropic_max", "Claude Max"),
                    ("github_copilot", "GitHub Copilot"),
                ];

                for (id, name) in providers {
                    if let Ok(Some(tokens)) = keyring.get_oauth_tokens(id) {
                        if let Some(expires_at) = tokens.expires_at {
                            let expires = chrono::DateTime::from_timestamp(expires_at, 0).unwrap();
                            let now = chrono::Utc::now();
                            if expires > now {
                                let remaining = expires - now;
                                let hours = remaining.num_hours();
                                let minutes = remaining.num_minutes();

                                let time_str = if hours > 0 {
                                    format!("{} hours", hours)
                                } else if minutes > 0 {
                                    format!("{} minutes", minutes)
                                } else {
                                    format!("{} seconds", remaining.num_seconds())
                                };

                                println!("✅ {}: authenticated ({} remaining)", name, time_str);
                            } else {
                                println!("⚠️  {}: expired (will auto-refresh)", name);
                            }
                        }
                    } else {
                        println!("❌ {}: not authenticated", name);
                    }
                }
                println!();
            }

            "clear" => {
                keyring.delete_oauth_tokens("github_copilot")?;
                keyring.delete_oauth_tokens("anthropic_max")?;

                println!("\n✅ All tokens cleared from keyring\n");
            }

            _ => {
                eprintln!("Unknown auth command: {}", args[2]);
                eprintln!("Use: claude, copilot, status, or clear");
                std::process::exit(1);
            }
        }

        return Ok(());
    }

    // Normal server startup
    // Initialize logging
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    info!("🚀 Thanos AI Gateway v{}", thanos::VERSION);
    info!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    // Load configuration
    let config = Config::load()?;
    info!("✓ Configuration loaded");
    info!("  HTTP: {}", config.server.bind);
    info!("  gRPC: {}", config.server.grpc);

    // Initialize models.dev (fetch model metadata in background)
    if config.models_dev.enabled {
        info!("✓ Fetching model metadata from models.dev...");
        tokio::spawn(async {
            use thanos::models_dev::MODELS_DEV_CLIENT;
            if let Err(e) = MODELS_DEV_CLIENT.fetch_models().await {
                tracing::warn!("Failed to fetch models.dev data: {}. Using fallback pricing.", e);
            } else {
                tracing::info!("✓ Loaded model metadata from models.dev");
            }
        });
    }

    // Start servers (HTTP + gRPC concurrently)
    server::run(config).await?;

    Ok(())
}

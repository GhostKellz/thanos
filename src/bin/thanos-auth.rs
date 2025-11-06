/// Thanos OAuth CLI Tool
/// Usage:
///   cargo run --bin thanos-auth-claude
///   cargo run --bin thanos-auth-copilot

use thanos::auth::{AnthropicOAuth, GitHubOAuth, KeyringStore, OAuthTokens};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let bin_name = args[0].split('/').last().unwrap_or("");

    // Auto-detect command from binary name, or use first arg
    let command = if bin_name.contains("claude") {
        "anthropic"
    } else if bin_name.contains("copilot") {
        "github"
    } else if args.len() >= 2 {
        args[1].as_str()
    } else {
        eprintln!("Usage: thanos-auth-claude OR thanos-auth-copilot");
        eprintln!("  Or: thanos-auth <github|anthropic|status|clear>");
        std::process::exit(1);
    };

    let keyring = KeyringStore::new("thanos");

    match command {
        "github" => {
            println!("Starting GitHub OAuth Device Flow...\n");

            let oauth = GitHubOAuth::new();
            let (github_token, copilot_token, expires_at) = oauth.authorize().await?;

            // Store tokens in keyring
            let tokens = OAuthTokens {
                access_token: copilot_token,
                refresh_token: Some(github_token),
                expires_at: Some(expires_at),
            };

            keyring.store_oauth_tokens("github_copilot", &tokens)?;

            println!("✅ Tokens stored in system keyring!");
            println!("   Provider: github_copilot");
            println!("   Expires: {}", chrono::DateTime::from_timestamp(expires_at, 0).unwrap());
        }

        "anthropic" => {
            println!("Starting Anthropic Claude Max OAuth (PKCE)...\n");

            let oauth = AnthropicOAuth::new();
            let token_response = oauth.authorize().await?;

            // Calculate expiry timestamp
            let expires_at = chrono::Utc::now().timestamp() + token_response.expires_in as i64;

            // Store tokens in keyring
            let tokens = OAuthTokens {
                access_token: token_response.access_token,
                refresh_token: Some(token_response.refresh_token),
                expires_at: Some(expires_at),
            };

            keyring.store_oauth_tokens("anthropic_max", &tokens)?;

            println!("✅ Tokens stored in system keyring!");
            println!("   Provider: anthropic_max");
            println!("   Expires: {}", chrono::DateTime::from_timestamp(expires_at, 0).unwrap());
        }

        "status" => {
            println!("🔐 Authentication Status\n");

            let providers = vec![
                ("github_copilot", "GitHub Copilot"),
                ("anthropic_max", "Anthropic Claude Max"),
            ];

            for (id, name) in providers {
                if let Ok(Some(tokens)) = keyring.get_oauth_tokens(id) {
                    println!("✅ {}", name);
                    println!("   Provider ID: {}", id);
                    if let Some(expires_at) = tokens.expires_at {
                        let expires = chrono::DateTime::from_timestamp(expires_at, 0).unwrap();
                        let now = chrono::Utc::now();
                        if expires > now {
                            let remaining = expires - now;
                            println!("   Expires: {} ({} hours remaining)", expires, remaining.num_hours());
                        } else {
                            println!("   Status: ⚠️  EXPIRED");
                        }
                    }
                    println!();
                } else {
                    println!("❌ {}", name);
                    println!("   Status: Not authenticated");
                    println!();
                }
            }
        }

        "clear" => {
            println!("Clearing all stored tokens...\n");

            keyring.delete_oauth_tokens("github_copilot")?;
            keyring.delete_oauth_tokens("anthropic_max")?;

            println!("✅ All tokens cleared from keyring");
        }

        _ => {
            eprintln!("Unknown command: {}", command);
            eprintln!("Use: github, anthropic, status, or clear");
            std::process::exit(1);
        }
    }

    Ok(())
}

/// Token manager with auto-refresh capabilities
use anyhow::Result;
use chrono::Utc;

use super::{AnthropicOAuth, GitHubOAuth, KeyringStore, OAuthTokens};

pub struct TokenManager {
    keyring: KeyringStore,
}

impl TokenManager {
    pub fn new() -> Self {
        Self {
            keyring: KeyringStore::new("thanos"),
        }
    }

    /// Get valid access token, automatically refreshing if expired
    pub async fn get_access_token(&self, provider: &str) -> Result<String> {
        let tokens = self
            .keyring
            .get_oauth_tokens(provider)?
            .ok_or_else(|| anyhow::anyhow!("No tokens found for provider: {}", provider))?;

        // Check if token is expired (with 5 minute buffer)
        let now = Utc::now().timestamp();
        let is_expired = tokens
            .expires_at
            .map(|exp| exp - 300 < now) // 5 minute buffer
            .unwrap_or(false);

        if is_expired {
            // Token is expired, attempt to refresh
            self.refresh_token(provider, &tokens).await
        } else {
            // Token is still valid
            Ok(tokens.access_token)
        }
    }

    /// Refresh token for a provider
    async fn refresh_token(&self, provider: &str, tokens: &OAuthTokens) -> Result<String> {
        let refresh_token = tokens
            .refresh_token
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("No refresh token available"))?;

        match provider {
            "anthropic_max" => {
                let oauth = AnthropicOAuth::new();
                let token_response = oauth.refresh_token(refresh_token).await?;

                let expires_at = Utc::now().timestamp() + token_response.expires_in as i64;

                let new_tokens = OAuthTokens {
                    access_token: token_response.access_token.clone(),
                    refresh_token: Some(token_response.refresh_token),
                    expires_at: Some(expires_at),
                };

                self.keyring.store_oauth_tokens(provider, &new_tokens)?;

                Ok(token_response.access_token)
            }
            "github_copilot" => {
                // For GitHub Copilot, the "refresh_token" is actually the GitHub access token
                let oauth = GitHubOAuth::new();
                let (copilot_token, expires_at) = oauth.get_copilot_token(refresh_token).await?;

                let new_tokens = OAuthTokens {
                    access_token: copilot_token.clone(),
                    refresh_token: Some(refresh_token.to_string()),
                    expires_at: Some(expires_at),
                };

                self.keyring.store_oauth_tokens(provider, &new_tokens)?;

                Ok(copilot_token)
            }
            _ => Err(anyhow::anyhow!(
                "Auto-refresh not supported for provider: {}",
                provider
            )),
        }
    }

    /// Check if token is expired or about to expire
    pub fn is_token_expired(&self, provider: &str) -> Result<bool> {
        let tokens = self
            .keyring
            .get_oauth_tokens(provider)?
            .ok_or_else(|| anyhow::anyhow!("No tokens found for provider: {}", provider))?;

        let now = Utc::now().timestamp();
        Ok(tokens
            .expires_at
            .map(|exp| exp < now)
            .unwrap_or(false))
    }

    /// Get time until expiration in seconds
    pub fn time_until_expiration(&self, provider: &str) -> Result<Option<i64>> {
        let tokens = self
            .keyring
            .get_oauth_tokens(provider)?
            .ok_or_else(|| anyhow::anyhow!("No tokens found for provider: {}", provider))?;

        let now = Utc::now().timestamp();
        Ok(tokens.expires_at.map(|exp| exp - now))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_manager_creation() {
        let _manager = TokenManager::new();
    }
}

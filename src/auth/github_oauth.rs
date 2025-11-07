/// GitHub OAuth Device Flow (like VS Code / OpenCode)
/// Used for GitHub Copilot access
use anyhow::Result;
use serde::Deserialize;
use std::time::Duration;

const CLIENT_ID: &str = "Iv1.b507a08c87ecfe98"; // VS Code's public client
const DEVICE_CODE_URL: &str = "https://github.com/login/device/code";
const TOKEN_URL: &str = "https://github.com/login/oauth/access_token";
const COPILOT_TOKEN_URL: &str = "https://api.github.com/copilot_internal/v2/token";
const SCOPES: &str = "read:user";

#[derive(Deserialize)]
struct DeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    #[allow(dead_code)]
    expires_in: u64,
    interval: u64,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    #[allow(dead_code)]
    token_type: String,
    #[allow(dead_code)]
    scope: String,
}

#[derive(Deserialize)]
struct CopilotTokenResponse {
    token: String,
    expires_at: i64,
}

pub struct GitHubOAuth {
    client: reqwest::Client,
}

impl Default for GitHubOAuth {
    fn default() -> Self {
        Self::new()
    }
}

impl GitHubOAuth {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }

    /// Initiate Device Flow - returns (user_code, verification_uri, device_code, interval)
    pub async fn initiate_device_flow(&self) -> Result<(String, String, String, u64)> {
        let params = [
            ("client_id", CLIENT_ID),
            ("scope", SCOPES),
        ];

        let res = self
            .client
            .post(DEVICE_CODE_URL)
            .form(&params)
            .header("Accept", "application/json")
            .send()
            .await?;

        if !res.status().is_success() {
            anyhow::bail!("Failed to get device code: {}", res.status());
        }

        let device_response: DeviceCodeResponse = res.json().await?;

        Ok((
            device_response.user_code,
            device_response.verification_uri,
            device_response.device_code,
            device_response.interval,
        ))
    }

    /// Poll for access token (call this in a loop)
    pub async fn poll_for_token(&self, device_code: &str) -> Result<Option<String>> {
        let params = [
            ("client_id", CLIENT_ID),
            ("device_code", device_code),
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
        ];

        let res = self
            .client
            .post(TOKEN_URL)
            .form(&params)
            .header("Accept", "application/json")
            .send()
            .await?;

        let text = res.text().await?;

        // Try to parse as TokenResponse
        if let Ok(token_response) = serde_json::from_str::<TokenResponse>(&text) {
            return Ok(Some(token_response.access_token));
        }

        // Check for error response
        #[derive(Deserialize)]
        struct ErrorResponse {
            error: String,
        }

        if let Ok(error_response) = serde_json::from_str::<ErrorResponse>(&text) {
            match error_response.error.as_str() {
                "authorization_pending" => return Ok(None), // Still waiting
                "slow_down" => return Ok(None),             // Poll slower
                "expired_token" => anyhow::bail!("Device code expired"),
                "access_denied" => anyhow::bail!("User denied access"),
                other => anyhow::bail!("OAuth error: {}", other),
            }
        }

        // Unknown response
        Ok(None)
    }

    /// Exchange GitHub token for Copilot token
    pub async fn get_copilot_token(&self, github_token: &str) -> Result<(String, i64)> {
        let res = self
            .client
            .get(COPILOT_TOKEN_URL)
            .header("Authorization", format!("Bearer {}", github_token))
            .header("Accept", "application/json")
            .header("User-Agent", "Thanos-AI-Gateway/0.1.0")
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("Failed to get Copilot token: {}", error_text);
        }

        let copilot_response: CopilotTokenResponse = res.json().await?;
        Ok((copilot_response.token, copilot_response.expires_at))
    }

    /// Complete OAuth flow (blocking until user authorizes)
    pub async fn authorize(&self) -> Result<(String, String, i64)> {
        println!("\n🔐 GitHub Copilot OAuth");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // Step 1: Get device code
        let (user_code, verification_uri, device_code, interval) = self.initiate_device_flow().await?;

        println!("\n📱 Opening browser...\n");
        println!("Steps:");
        println!("  1. Visit: {}", verification_uri);
        println!("  2. Enter code: {}", user_code);
        println!("  3. Authorize the application");
        println!("  4. Close the browser tab after authorization\n");

        // Try to open browser
        let _ = opener::open(&verification_uri);

        print!("⏳ Waiting for authorization...");
        use std::io::Write;
        std::io::stdout().flush().ok();

        // Step 2: Poll for token
        let mut attempts = 0;
        let max_attempts = 60; // 5 minutes with 5-second intervals
        let poll_interval = Duration::from_secs(interval);

        let github_token = loop {
            tokio::time::sleep(poll_interval).await;

            match self.poll_for_token(&device_code).await? {
                Some(token) => break token,
                None => {
                    attempts += 1;
                    if attempts >= max_attempts {
                        anyhow::bail!("Timeout waiting for authorization");
                    }
                }
            }
        };

        println!(" ✓\n");

        // Step 3: Get Copilot token
        print!("⏳ Obtaining Copilot token...");
        std::io::stdout().flush().ok();
        let (copilot_token, expires_at) = self.get_copilot_token(&github_token).await?;
        println!(" ✓\n");

        println!("✅ Authenticated successfully");

        Ok((github_token, copilot_token, expires_at))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires user interaction
    async fn test_device_flow() {
        let oauth = GitHubOAuth::new();
        let (user_code, verification_uri, _, _) = oauth.initiate_device_flow().await.unwrap();

        println!("User code: {}", user_code);
        println!("Verification URI: {}", verification_uri);
    }
}

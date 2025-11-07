/// Anthropic Claude Max OAuth (PKCE Flow - like OpenCode)
/// Use your $20/month Claude Max subscription instead of API billing
use anyhow::Result;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const CLIENT_ID: &str = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"; // Public client ID
const AUTH_URL: &str = "https://console.anthropic.com/oauth/authorize";
const TOKEN_URL: &str = "https://console.anthropic.com/v1/oauth/token";
const REDIRECT_URI: &str = "https://console.anthropic.com/oauth/code/callback";
const SCOPES: &str = "org:create_api_key user:profile user:inference";

#[derive(Serialize)]
struct TokenRequest {
    code: String,
    state: String,
    grant_type: String,
    client_id: String,
    redirect_uri: String,
    code_verifier: String,
}

#[derive(Deserialize)]
pub struct TokenResponse {
    pub token_type: String,
    pub access_token: String,
    pub expires_in: u64, // 28800 seconds (8 hours)
    pub refresh_token: String,
    pub scope: String,
    pub organization: Option<Organization>,
    pub account: Option<Account>,
}

#[derive(Deserialize)]
pub struct Organization {
    pub uuid: String,
    pub name: String,
}

#[derive(Deserialize)]
pub struct Account {
    pub uuid: String,
    pub email_address: String,
}

pub struct AnthropicOAuth {
    client: reqwest::Client,
}

impl Default for AnthropicOAuth {
    fn default() -> Self {
        Self::new()
    }
}

impl AnthropicOAuth {
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::new(),
        }
    }

    /// Generate PKCE code verifier (43-128 characters per RFC 7636)
    fn generate_code_verifier() -> String {
        use rand::RngCore;
        let mut rng = rand::thread_rng();
        let mut random_bytes = vec![0u8; 32]; // 32 bytes = 43 chars base64
        rng.fill_bytes(&mut random_bytes);
        URL_SAFE_NO_PAD.encode(random_bytes)
    }

    /// Generate PKCE code challenge (SHA-256 of verifier)
    fn generate_code_challenge(verifier: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(verifier.as_bytes());
        let hash = hasher.finalize();
        URL_SAFE_NO_PAD.encode(hash)
    }

    /// Generate random state for CSRF protection
    fn generate_state() -> String {
        use rand::RngCore;
        let mut rng = rand::thread_rng();
        let mut random_bytes = vec![0u8; 32];
        rng.fill_bytes(&mut random_bytes);
        URL_SAFE_NO_PAD.encode(random_bytes)
    }

    /// Build authorization URL
    pub fn build_auth_url(&self) -> (String, String, String) {
        let code_verifier = Self::generate_code_verifier();
        let code_challenge = Self::generate_code_challenge(&code_verifier);
        let state = Self::generate_state();

        let auth_url = format!(
            "{}?code=true&client_id={}&response_type=code&redirect_uri={}&scope={}&code_challenge={}&code_challenge_method=S256&state={}",
            AUTH_URL,
            CLIENT_ID,
            urlencoding::encode(REDIRECT_URI),
            urlencoding::encode(SCOPES),
            code_challenge,
            state
        );

        (auth_url, code_verifier, state)
    }

    /// Exchange authorization code for tokens
    pub async fn exchange_code(
        &self,
        code: &str,
        state: &str,
        code_verifier: &str,
    ) -> Result<TokenResponse> {
        let token_request = TokenRequest {
            code: code.to_string(),
            state: state.to_string(),
            grant_type: "authorization_code".to_string(),
            client_id: CLIENT_ID.to_string(),
            redirect_uri: REDIRECT_URI.to_string(),
            code_verifier: code_verifier.to_string(),
        };

        let res = self
            .client
            .post(TOKEN_URL)
            .json(&token_request)
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("Token exchange failed: {}", error_text);
        }

        let token_response: TokenResponse = res.json().await?;
        Ok(token_response)
    }

    /// Refresh access token using refresh token
    pub async fn refresh_token(&self, refresh_token: &str) -> Result<TokenResponse> {
        #[derive(Serialize)]
        struct RefreshRequest {
            grant_type: String,
            refresh_token: String,
            client_id: String,
        }

        let refresh_request = RefreshRequest {
            grant_type: "refresh_token".to_string(),
            refresh_token: refresh_token.to_string(),
            client_id: CLIENT_ID.to_string(),
        };

        let res = self
            .client
            .post(TOKEN_URL)
            .json(&refresh_request)
            .send()
            .await?;

        if !res.status().is_success() {
            let error_text = res.text().await?;
            anyhow::bail!("Token refresh failed: {}", error_text);
        }

        let token_response: TokenResponse = res.json().await?;
        Ok(token_response)
    }

    /// Complete OAuth flow (like OpenCode - manual code entry)
    pub async fn authorize(&self) -> Result<TokenResponse> {
        println!("\n🔐 Anthropic Claude Max OAuth");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        // Step 1: Generate PKCE parameters and auth URL
        let (auth_url, code_verifier, expected_state) = self.build_auth_url();

        println!("\n📱 Opening browser...\n");
        println!("   {}\n", auth_url);

        // Try to open browser
        let _ = opener::open(&auth_url);

        println!("Steps:");
        println!("  1. Log in with your Claude Max account");
        println!("  2. Click \"Authorize\" to grant access");
        println!("  3. Copy the authorization code (format: code#state)");
        println!("  4. Close the browser tab after copying\n");

        // Step 2: Prompt user to paste the code
        print!("📋 Paste authorization code: ");
        use std::io::Write;
        std::io::stdout().flush()?;

        let mut code_input = String::new();
        std::io::stdin().read_line(&mut code_input)?;
        let code_input = code_input.trim();

        // Parse code#state format
        let (code, state) = if let Some(idx) = code_input.find('#') {
            let code = &code_input[..idx];
            let state = &code_input[idx + 1..];
            (code, state)
        } else {
            anyhow::bail!("Invalid format. Expected: code#state");
        };

        // Verify state (CSRF protection)
        if state != expected_state {
            anyhow::bail!("State mismatch - possible CSRF attack!");
        }

        print!("\n⏳ Exchanging code for tokens...");
        std::io::stdout().flush()?;

        // Step 3: Exchange code for tokens
        let token_response = self.exchange_code(code, state, &code_verifier).await?;

        println!(" ✓\n");

        if let Some(ref account) = token_response.account {
            println!("✅ Authenticated as: {}", account.email_address);
        }

        if let Some(ref org) = token_response.organization {
            println!("   Organization: {}", org.name);
        }

        Ok(token_response)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pkce_generation() {
        let verifier = AnthropicOAuth::generate_code_verifier();
        let challenge = AnthropicOAuth::generate_code_challenge(&verifier);

        assert!(!verifier.is_empty());
        assert!(!challenge.is_empty());
        assert_ne!(verifier, challenge);
    }

    #[test]
    fn test_auth_url() {
        let oauth = AnthropicOAuth::new();
        let (url, verifier, state) = oauth.build_auth_url();

        assert!(url.contains("console.anthropic.com"));
        assert!(url.contains("code_challenge"));
        assert!(!verifier.is_empty());
        assert!(!state.is_empty());
    }
}

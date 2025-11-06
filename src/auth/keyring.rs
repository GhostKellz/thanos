/// System keyring integration for secure OAuth token storage
/// Uses native keyring: Secret Service (Linux), Keychain (macOS), Credential Manager (Windows)
use anyhow::Result;
use keyring::Entry;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct OAuthTokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at: Option<i64>, // Unix timestamp
}

pub struct KeyringStore {
    service: String,
}

impl KeyringStore {
    pub fn new(service: &str) -> Self {
        Self {
            service: service.to_string(),
        }
    }

    /// Store OAuth tokens in system keyring
    pub fn store_oauth_tokens(&self, provider: &str, tokens: &OAuthTokens) -> Result<()> {
        let entry = Entry::new(&self.service, provider)?;
        let json = serde_json::to_string(tokens)?;
        entry.set_password(&json)?;
        Ok(())
    }

    /// Retrieve OAuth tokens from system keyring
    pub fn get_oauth_tokens(&self, provider: &str) -> Result<Option<OAuthTokens>> {
        let entry = Entry::new(&self.service, provider)?;
        match entry.get_password() {
            Ok(json) => {
                let tokens: OAuthTokens = serde_json::from_str(&json)?;
                Ok(Some(tokens))
            }
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Delete OAuth tokens from system keyring
    pub fn delete_oauth_tokens(&self, provider: &str) -> Result<()> {
        let entry = Entry::new(&self.service, provider)?;
        match entry.delete_password() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()), // Already deleted
            Err(e) => Err(e.into()),
        }
    }

    /// Check if tokens exist for provider
    pub fn has_tokens(&self, provider: &str) -> bool {
        self.get_oauth_tokens(provider).ok().flatten().is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore] // Requires system keyring
    fn test_keyring_roundtrip() {
        let store = KeyringStore::new("thanos-test");
        let tokens = OAuthTokens {
            access_token: "test-access-token".to_string(),
            refresh_token: Some("test-refresh-token".to_string()),
            expires_at: Some(1234567890),
        };

        // Store
        store.store_oauth_tokens("test-provider", &tokens).unwrap();

        // Retrieve
        let retrieved = store.get_oauth_tokens("test-provider").unwrap().unwrap();
        assert_eq!(retrieved.access_token, tokens.access_token);
        assert_eq!(retrieved.refresh_token, tokens.refresh_token);

        // Delete
        store.delete_oauth_tokens("test-provider").unwrap();
        assert!(store.get_oauth_tokens("test-provider").unwrap().is_none());
    }
}

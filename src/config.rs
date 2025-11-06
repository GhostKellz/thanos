use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, env, fs, path::Path};

use crate::types::AuthMethod;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub routing: RoutingConfig,
    pub providers: HashMap<String, ProviderConfig>,
    #[serde(default)]
    pub models_dev: ModelsDevConfig,
    #[serde(default)]
    pub cache: CacheConfig,
    #[serde(default)]
    pub rate_limiting: RateLimitingConfig,
    #[serde(default)]
    pub metrics: MetricsConfig,
    #[serde(default)]
    pub oauth: OAuthConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_http_bind")]
    pub bind: String,
    #[serde(default = "default_grpc_bind")]
    pub grpc: String,
    #[serde(default = "default_log_level")]
    pub log_level: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uds_path: Option<String>,
    #[serde(default = "default_true")]
    pub uds_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingConfig {
    #[serde(default = "default_strategy")]
    pub strategy: String,
    #[serde(default)]
    pub fallback_chain: Vec<String>,
    #[serde(default)]
    pub load_balance: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfig {
    #[serde(default)]
    pub enabled: bool,
    pub auth_method: AuthMethod,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub api_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub base_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endpoint: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelsDevConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_models_dev_url")]
    pub url: String,
    #[serde(default = "default_cache_ttl")]
    pub cache_ttl: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default = "default_cache_ttl")]
    pub ttl: u64,
    #[serde(default = "default_max_size")]
    pub max_size: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitingConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default = "default_rpm")]
    pub requests_per_minute: u32,
    #[serde(default = "default_rph")]
    pub requests_per_hour: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default = "default_prometheus_port")]
    pub prometheus_port: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthConfig {
    #[serde(default = "default_true")]
    pub auto_refresh: bool,
    #[serde(default = "default_refresh_warning")]
    pub refresh_warning_hours: u64,
    #[serde(default = "default_keyring_service")]
    pub keyring_service: String,
}

// Defaults
fn default_http_bind() -> String { "0.0.0.0:8080".to_string() }
fn default_grpc_bind() -> String { "0.0.0.0:50051".to_string() }
fn default_log_level() -> String { "info".to_string() }
fn default_strategy() -> String { "preferred".to_string() }
fn default_true() -> bool { true }
fn default_models_dev_url() -> String { "https://models.dev/api.json".to_string() }
fn default_cache_ttl() -> u64 { 3600 }
fn default_max_size() -> usize { 1000 }
fn default_rpm() -> u32 { 60 }
fn default_rph() -> u32 { 1000 }
fn default_prometheus_port() -> u16 { 9090 }
fn default_refresh_warning() -> u64 { 2 }
fn default_keyring_service() -> String { "thanos".to_string() }

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            bind: default_http_bind(),
            grpc: default_grpc_bind(),
            log_level: default_log_level(),
            uds_path: None,
            uds_enabled: true,
        }
    }
}

impl Default for RoutingConfig {
    fn default() -> Self {
        Self {
            strategy: default_strategy(),
            fallback_chain: vec![],
            load_balance: vec![],
        }
    }
}

impl Default for ModelsDevConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            url: default_models_dev_url(),
            cache_ttl: default_cache_ttl(),
        }
    }
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            ttl: default_cache_ttl(),
            max_size: default_max_size(),
        }
    }
}

impl Default for RateLimitingConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            requests_per_minute: default_rpm(),
            requests_per_hour: default_rph(),
        }
    }
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            prometheus_port: default_prometheus_port(),
        }
    }
}

impl Default for OAuthConfig {
    fn default() -> Self {
        Self {
            auto_refresh: true,
            refresh_warning_hours: default_refresh_warning(),
            keyring_service: default_keyring_service(),
        }
    }
}

impl Config {
    /// Load configuration from file and environment
    pub fn load() -> Result<Self> {
        // Load .env file if it exists
        dotenvy::dotenv().ok();

        // Try to find config file
        let config_path = env::var("THANOS_CONFIG")
            .unwrap_or_else(|_| {
                // Check common locations
                let home_config = format!("{}/.config/thanos/config.toml", env::var("HOME").unwrap_or_default());
                let locations = vec![
                    "./config.toml",
                    "./thanos.toml",
                    "/etc/thanos/config.toml",
                    home_config.as_str(),
                ];

                for path in locations {
                    if Path::new(path).exists() {
                        return path.to_string();
                    }
                }

                // Default
                "./config.toml".to_string()
            });

        // Validate config file permissions on Unix systems
        #[cfg(unix)]
        Self::validate_file_permissions(&config_path)?;

        let config_content = fs::read_to_string(&config_path)
            .with_context(|| format!("Failed to read config file: {}", config_path))?;

        // Substitute environment variables
        let config_content = Self::substitute_env_vars(&config_content);

        // Parse TOML
        let mut config: Config = toml::from_str(&config_content)
            .with_context(|| format!("Failed to parse config file: {}", config_path))?;

        // Validate providers
        config.validate_providers()?;

        Ok(config)
    }

    /// Substitute ${VAR_NAME} with environment variable values
    fn substitute_env_vars(content: &str) -> String {
        let mut result = content.to_string();

        // Find all ${VAR} patterns
        while let Some(start) = result.find("${") {
            if let Some(end) = result[start..].find('}') {
                let var_name = &result[start + 2..start + end];
                let value = env::var(var_name).unwrap_or_default();
                result.replace_range(start..start + end + 1, &value);
            } else {
                break;
            }
        }

        result
    }

    /// Validate provider configurations
    fn validate_providers(&mut self) -> Result<()> {
        for (name, provider) in &self.providers {
            if !provider.enabled {
                continue;
            }

            match provider.auth_method {
                AuthMethod::ApiKey => {
                    if provider.api_key.is_none() || provider.api_key.as_ref().unwrap().is_empty() {
                        tracing::warn!(
                            "Provider '{}' enabled but missing API key - will be disabled",
                            name
                        );
                    }
                }
                AuthMethod::OAuth => {
                    // OAuth tokens will be loaded from keyring
                    tracing::debug!("Provider '{}' uses OAuth - tokens loaded from keyring", name);
                }
                AuthMethod::None => {
                    // No auth required (e.g., Ollama)
                }
            }
        }

        Ok(())
    }

    /// Get enabled providers
    pub fn enabled_providers(&self) -> Vec<(String, &ProviderConfig)> {
        self.providers
            .iter()
            .filter(|(_, config)| config.enabled)
            .map(|(name, config)| (name.clone(), config))
            .collect()
    }

    /// Validate config file permissions (Unix only)
    #[cfg(unix)]
    fn validate_file_permissions(path: &str) -> Result<()> {
        use std::os::unix::fs::PermissionsExt;

        let path_obj = Path::new(path);

        // Skip validation if file doesn't exist yet (first run)
        if !path_obj.exists() {
            tracing::debug!("Config file does not exist yet: {}", path);
            return Ok(());
        }

        let metadata = fs::metadata(path_obj)
            .with_context(|| format!("Failed to read metadata for config file: {}", path))?;

        let permissions = metadata.permissions();
        let mode = permissions.mode();

        // Check if file is readable by group or others (we want 0600 or 0400)
        let group_readable = (mode & 0o040) != 0;
        let others_readable = (mode & 0o004) != 0;
        let group_writable = (mode & 0o020) != 0;
        let others_writable = (mode & 0o002) != 0;

        if group_readable || others_readable {
            tracing::warn!(
                "⚠️  Config file {} has insecure permissions: {:o}",
                path,
                mode & 0o777
            );
            tracing::warn!(
                "   Recommended: chmod 600 {} (to make it readable/writable only by owner)",
                path
            );
            tracing::warn!(
                "   This file may contain API keys and should not be readable by other users."
            );
        }

        if group_writable || others_writable {
            anyhow::bail!(
                "Config file {} is writable by group or others (mode: {:o}). \
                This is a security risk. Run: chmod 600 {}",
                path,
                mode & 0o777,
                path
            );
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_env_var_substitution() {
        env::set_var("TEST_VAR", "test_value");

        let input = "api_key = \"${TEST_VAR}\"";
        let output = Config::substitute_env_vars(input);

        assert_eq!(output, "api_key = \"test_value\"");

        env::remove_var("TEST_VAR");
    }

    #[test]
    fn test_env_var_substitution_multiple() {
        env::set_var("VAR1", "value1");
        env::set_var("VAR2", "value2");

        let input = "key1 = \"${VAR1}\"\nkey2 = \"${VAR2}\"";
        let output = Config::substitute_env_vars(input);

        assert!(output.contains("value1"));
        assert!(output.contains("value2"));

        env::remove_var("VAR1");
        env::remove_var("VAR2");
    }

    #[test]
    fn test_enabled_providers_filter() {
        let mut providers = HashMap::new();

        providers.insert(
            "enabled1".to_string(),
            ProviderConfig {
                enabled: true,
                auth_method: AuthMethod::ApiKey,
                api_key: Some("key1".to_string()),
                base_url: None,
                endpoint: None,
                model: None,
                max_tokens: None,
                temperature: None,
                client_id: None,
            },
        );

        providers.insert(
            "disabled".to_string(),
            ProviderConfig {
                enabled: false,
                auth_method: AuthMethod::None,
                api_key: None,
                base_url: None,
                endpoint: None,
                model: None,
                max_tokens: None,
                temperature: None,
                client_id: None,
            },
        );

        let config = Config {
            server: Default::default(),
            routing: Default::default(),
            providers,
            models_dev: Default::default(),
            cache: Default::default(),
            rate_limiting: Default::default(),
            metrics: Default::default(),
            oauth: Default::default(),
        };

        let enabled = config.enabled_providers();
        assert_eq!(enabled.len(), 1);
        assert_eq!(enabled[0].0, "enabled1");
    }
}

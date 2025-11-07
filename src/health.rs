use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use tokio::sync::RwLock;

/// Health status for a single provider
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

/// Health check result for a provider
#[derive(Debug, Clone, Serialize)]
pub struct ProviderHealth {
    pub status: HealthStatus,
    pub latency_ms: Option<u64>,
    pub last_check: u64,
    pub error: Option<String>,
}

/// Cached health results
struct HealthCache {
    results: HashMap<String, (ProviderHealth, SystemTime)>,
    ttl: Duration,
}

impl HealthCache {
    fn new(ttl_seconds: u64) -> Self {
        Self {
            results: HashMap::new(),
            ttl: Duration::from_secs(ttl_seconds),
        }
    }

    fn get(&self, provider: &str) -> Option<ProviderHealth> {
        self.results.get(provider).and_then(|(health, timestamp)| {
            if timestamp.elapsed().ok()? < self.ttl {
                Some(health.clone())
            } else {
                None
            }
        })
    }

    fn set(&mut self, provider: String, health: ProviderHealth) {
        self.results.insert(provider, (health, SystemTime::now()));
    }
}

/// Health checker with caching
pub struct HealthChecker {
    cache: Arc<RwLock<HealthCache>>,
}

impl HealthChecker {
    pub fn new() -> Self {
        Self {
            cache: Arc::new(RwLock::new(HealthCache::new(30))), // 30s TTL
        }
    }

    /// Check health of a provider (with caching)
    pub async fn check_provider(&self, provider: &str, endpoint: &str) -> ProviderHealth {
        // Check cache first
        {
            let cache = self.cache.read().await;
            if let Some(cached) = cache.get(provider) {
                return cached;
            }
        }

        // Perform actual health check
        let health = self.ping_endpoint(provider, endpoint).await;

        // Update cache
        {
            let mut cache = self.cache.write().await;
            cache.set(provider.to_string(), health.clone());
        }

        health
    }

    /// Ping a provider endpoint
    async fn ping_endpoint(&self, provider: &str, base_url: &str) -> ProviderHealth {
        let start = SystemTime::now();
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap();

        // Provider-specific health check endpoints
        let (url, method) = match provider {
            "anthropic" => (format!("{}/v1/messages", base_url), "POST"),
            "openai" => (format!("{}/v1/models", base_url), "GET"),
            "gemini" => (format!("{}/v1beta/models", base_url), "GET"),
            "xai" => (format!("{}/v1/models", base_url), "GET"),
            "ollama" => (format!("{}/api/tags", base_url), "GET"),
            "github_copilot" => {
                // GitHub Copilot requires auth, just check GitHub API
                ("https://api.github.com/zen".to_string(), "GET")
            }
            _ => return ProviderHealth {
                status: HealthStatus::Unhealthy,
                latency_ms: None,
                last_check: SystemTime::now()
                    .duration_since(SystemTime::UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
                error: Some("Unknown provider".to_string()),
            },
        };

        let result = match method {
            "GET" => client.get(&url).send().await,
            "POST" => {
                // For POST endpoints, send minimal request
                client
                    .post(&url)
                    .header("Content-Type", "application/json")
                    .body("{}")
                    .send()
                    .await
            }
            _ => unreachable!(),
        };

        let latency = start.elapsed().ok().map(|d| d.as_millis() as u64);
        let timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        match result {
            Ok(response) => {
                let status_code = response.status().as_u16();
                let status = match status_code {
                    200..=299 => HealthStatus::Healthy,
                    400..=499 => {
                        // Client errors might mean endpoint exists but auth failed (healthy)
                        if status_code == 401 || status_code == 403 {
                            HealthStatus::Healthy // Auth error means service is up
                        } else {
                            HealthStatus::Degraded
                        }
                    }
                    500..=599 => HealthStatus::Degraded,
                    _ => HealthStatus::Unhealthy,
                };

                ProviderHealth {
                    status,
                    latency_ms: latency,
                    last_check: timestamp,
                    error: if status != HealthStatus::Healthy {
                        Some(format!("HTTP {}", status_code))
                    } else {
                        None
                    },
                }
            }
            Err(e) => {
                // Connection errors
                ProviderHealth {
                    status: HealthStatus::Unhealthy,
                    latency_ms: latency,
                    last_check: timestamp,
                    error: Some(format!("{}", e)),
                }
            }
        }
    }

    /// Check all providers in parallel
    pub async fn check_all(
        &self,
        providers: HashMap<String, String>,
    ) -> HashMap<String, ProviderHealth> {
        use futures::future::join_all;

        // Spawn parallel health checks
        let futures: Vec<_> = providers
            .into_iter()
            .map(|(provider, endpoint)| {
                let checker = self.clone();
                async move {
                    let health = checker.check_provider(&provider, &endpoint).await;
                    (provider, health)
                }
            })
            .collect();

        // Wait for all checks to complete
        let results = join_all(futures).await;

        // Convert to HashMap
        results.into_iter().collect()
    }

    /// Clone for parallel execution
    fn clone(&self) -> Self {
        Self {
            cache: Arc::clone(&self.cache),
        }
    }
}

impl Default for HealthChecker {
    fn default() -> Self {
        Self::new()
    }
}

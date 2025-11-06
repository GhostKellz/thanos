use crate::config::Config;
use crate::types::{ChatRequest, ChatResponse, Provider};
use anyhow::{anyhow, Result};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;
use tracing::{debug, warn};

/// Router for selecting and routing to providers
pub struct Router {
    config: Arc<Config>,
    cache: crate::cache::ResponseCache,
    circuit_breaker: crate::circuit_breaker::CircuitBreaker,
    round_robin_counter: AtomicUsize,
}

impl Router {
    pub fn new(config: Arc<Config>) -> Self {
        // Initialize cache and circuit breaker based on config
        let cache = crate::cache::ResponseCache::new(
            config.cache.max_size,
            config.cache.ttl,
        );

        let circuit_breaker = crate::circuit_breaker::CircuitBreaker::new(
            5,  // failure_threshold
            3,  // success_threshold
            30, // timeout_secs
        );

        Self {
            config,
            cache,
            circuit_breaker,
            round_robin_counter: AtomicUsize::new(0),
        }
    }

    /// Route a chat completion request to the appropriate provider
    pub async fn route_chat_completion(&self, request: &ChatRequest) -> Result<ChatResponse> {
        // Check cache first (skip for streaming requests)
        if !request.stream && self.config.cache.enabled {
            let cache_key = crate::cache::cache_key(request);
            if let Some(cached_response) = self.cache.get(&cache_key) {
                debug!("Cache hit for request");
                return Ok(cached_response);
            }
        }

        let strategy = &self.config.routing.strategy;
        let start = Instant::now();

        let result = match strategy.as_str() {
            "preferred" => self.route_preferred(request).await,
            "fallback" => self.route_fallback(request).await,
            "round-robin" => self.route_round_robin(request).await,
            "omen" => self.route_omen(request).await,
            _ => {
                warn!("Unknown routing strategy '{}', falling back to preferred", strategy);
                self.route_preferred(request).await
            }
        };

        // Record request duration
        let duration = start.elapsed().as_secs_f64();
        crate::metrics::METRICS.request_duration_seconds
            .with_label_values(&["chat_completions", "POST"])
            .observe(duration);

        // Cache successful responses
        if let Ok(ref response) = result {
            if !request.stream && self.config.cache.enabled {
                let cache_key = crate::cache::cache_key(request);
                self.cache.set(cache_key, response.clone());
            }

            // Record successful request
            crate::metrics::METRICS.requests_total
                .with_label_values(&["chat_completions", "POST", "200"])
                .inc();

            // Record token usage and cost
            if let Some(ref usage) = response.usage {
                crate::metrics::METRICS.tokens_used_total
                    .with_label_values(&[&response.provider, &response.model, "input"])
                    .inc_by(usage.prompt_tokens as f64);

                crate::metrics::METRICS.tokens_used_total
                    .with_label_values(&[&response.provider, &response.model, "output"])
                    .inc_by(usage.completion_tokens as f64);

                // Calculate and record cost
                if let Some(cost) = crate::models_dev::calculate_cost_with_fallback(
                    &response.model,
                    usage.prompt_tokens,
                    usage.completion_tokens,
                )
                .await
                {
                    crate::metrics::METRICS.estimated_cost_usd
                        .with_label_values(&[&response.provider, &response.model])
                        .inc_by(cost);
                }
            }
        } else {
            // Record failed request
            crate::metrics::METRICS.requests_total
                .with_label_values(&["chat_completions", "POST", "500"])
                .inc();
        }

        result
    }

    /// Stream a chat completion request to the appropriate provider
    pub async fn route_chat_completion_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<ChatResponse>>> {
        let strategy = &self.config.routing.strategy;

        match strategy.as_str() {
            "preferred" => self.stream_preferred(request).await,
            "fallback" => self.stream_fallback(request).await,
            "round-robin" => self.stream_round_robin(request).await,
            "omen" => self.stream_omen(request).await,
            _ => {
                warn!("Unknown routing strategy '{}', falling back to preferred", strategy);
                self.stream_preferred(request).await
            }
        }
    }

    /// Route to the first enabled provider
    async fn route_preferred(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let providers = self.config.enabled_providers();

        if providers.is_empty() {
            return Err(anyhow!("No enabled providers available"));
        }

        let (provider_name, provider_config) = &providers[0];
        debug!("Routing to preferred provider: {}", provider_name);

        self.call_provider(provider_name, provider_config, request).await
    }

    /// Try providers in fallback chain order
    async fn route_fallback(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let fallback_chain = &self.config.routing.fallback_chain;
        let enabled_providers: std::collections::HashMap<_, _> =
            self.config.enabled_providers().into_iter().collect();

        for provider_name in fallback_chain {
            if let Some(provider_config) = enabled_providers.get(provider_name) {
                debug!("Trying fallback provider: {}", provider_name);

                match self.call_provider(provider_name, provider_config, request).await {
                    Ok(response) => return Ok(response),
                    Err(e) => {
                        warn!("Provider {} failed: {}, trying next", provider_name, e);
                        continue;
                    }
                }
            }
        }

        Err(anyhow!("All providers in fallback chain failed"))
    }

    /// Round-robin load balancing with atomic counter
    async fn route_round_robin(&self, request: &ChatRequest) -> Result<ChatResponse> {
        let providers = self.config.enabled_providers();

        if providers.is_empty() {
            return Err(anyhow!("No enabled providers available"));
        }

        // Get next provider index using atomic counter
        let index = self.round_robin_counter.fetch_add(1, Ordering::Relaxed) % providers.len();
        let (provider_name, provider_config) = &providers[index];

        debug!("Round-robin routing to provider {} (index {})", provider_name, index);

        self.call_provider(provider_name, provider_config, request).await
    }

    /// Route through Omen for intelligent routing
    async fn route_omen(&self, _request: &ChatRequest) -> Result<ChatResponse> {
        // TODO: Implement Omen client integration
        Err(anyhow!("Omen routing not yet implemented"))
    }

    /// Stream from preferred provider
    async fn stream_preferred(
        &self,
        request: &ChatRequest,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<ChatResponse>>> {
        let providers = self.config.enabled_providers();

        if providers.is_empty() {
            return Err(anyhow!("No enabled providers available"));
        }

        let (provider_name, provider_config) = &providers[0];
        debug!("Streaming from preferred provider: {}", provider_name);

        self.stream_provider(provider_name, provider_config, request).await
    }

    /// Stream with fallback
    async fn stream_fallback(
        &self,
        request: &ChatRequest,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<ChatResponse>>> {
        let fallback_chain = &self.config.routing.fallback_chain;
        let enabled_providers: std::collections::HashMap<_, _> =
            self.config.enabled_providers().into_iter().collect();

        for provider_name in fallback_chain {
            if let Some(provider_config) = enabled_providers.get(provider_name) {
                debug!("Trying fallback stream provider: {}", provider_name);

                match self.stream_provider(provider_name, provider_config, request).await {
                    Ok(receiver) => return Ok(receiver),
                    Err(e) => {
                        warn!("Provider {} stream failed: {}, trying next", provider_name, e);
                        continue;
                    }
                }
            }
        }

        Err(anyhow!("All providers in fallback chain failed for streaming"))
    }

    /// Round-robin streaming with atomic counter
    async fn stream_round_robin(
        &self,
        request: &ChatRequest,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<ChatResponse>>> {
        let providers = self.config.enabled_providers();

        if providers.is_empty() {
            return Err(anyhow!("No enabled providers available"));
        }

        // Get next provider index using atomic counter
        let index = self.round_robin_counter.fetch_add(1, Ordering::Relaxed) % providers.len();
        let (provider_name, provider_config) = &providers[index];

        debug!("Round-robin streaming to provider {} (index {})", provider_name, index);

        self.stream_provider(provider_name, provider_config, request).await
    }

    /// Stream through Omen
    async fn stream_omen(
        &self,
        _request: &ChatRequest,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<ChatResponse>>> {
        Err(anyhow!("Omen streaming not yet implemented"))
    }

    /// Call a specific provider
    async fn call_provider(
        &self,
        provider_name: &str,
        provider_config: &crate::config::ProviderConfig,
        request: &ChatRequest,
    ) -> Result<ChatResponse> {
        // Check circuit breaker
        if !self.circuit_breaker.can_attempt(provider_name) {
            warn!("Circuit breaker open for provider: {}", provider_name);
            return Err(anyhow!("Circuit breaker open for provider: {}", provider_name));
        }

        let start = Instant::now();
        use crate::providers::{anthropic::AnthropicProvider, gemini::GeminiProvider,
                                github_copilot::GitHubCopilotProvider, ollama::OllamaProvider,
                                openai::OpenAIProvider, xai::XAIProvider};

        let result = match Provider::from_str(provider_name) {
            Some(Provider::Anthropic) | Some(Provider::AnthropicMax) => {
                let provider = AnthropicProvider::from_config(provider_config)?;
                provider.chat_completion(request).await
            }
            Some(Provider::OpenAI) => {
                let provider = OpenAIProvider::from_config(provider_config)?;
                provider.chat_completion(request).await
            }
            Some(Provider::Xai) => {
                let provider = XAIProvider::from_config(provider_config)?;
                provider.chat_completion(request).await
            }
            Some(Provider::Gemini) => {
                let provider = GeminiProvider::from_config(provider_config)?;
                provider.chat_completion(request).await
            }
            Some(Provider::Ollama) => {
                let provider = OllamaProvider::from_config(provider_config)?;
                provider.chat_completion(request).await
            }
            Some(Provider::GithubCopilot) => {
                let provider = GitHubCopilotProvider::from_config(provider_config)?;
                provider.chat_completion(request).await
            }
            Some(Provider::Omen) => {
                Err(anyhow!("Omen provider not yet implemented"))
            }
            None => Err(anyhow!("Unknown provider: {}", provider_name)),
        };

        // Record metrics and update circuit breaker
        let duration = start.elapsed().as_secs_f64();
        crate::metrics::METRICS.provider_duration_seconds
            .with_label_values(&[provider_name, &request.model])
            .observe(duration);

        match &result {
            Ok(_response) => {
                // Success
                self.circuit_breaker.record_success(provider_name);

                crate::metrics::METRICS.provider_requests_total
                    .with_label_values(&[provider_name, &request.model, "success"])
                    .inc();
            }
            Err(e) => {
                // Failure
                self.circuit_breaker.record_failure(provider_name);

                crate::metrics::METRICS.provider_requests_total
                    .with_label_values(&[provider_name, &request.model, "error"])
                    .inc();

                crate::metrics::METRICS.provider_errors_total
                    .with_label_values(&[provider_name, "api_error"])
                    .inc();

                warn!("Provider {} failed: {}", provider_name, e);
            }
        }

        result
    }

    /// Stream from a specific provider
    async fn stream_provider(
        &self,
        provider_name: &str,
        provider_config: &crate::config::ProviderConfig,
        request: &ChatRequest,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<ChatResponse>>> {
        use crate::providers::{anthropic::AnthropicProvider, gemini::GeminiProvider,
                                github_copilot::GitHubCopilotProvider, ollama::OllamaProvider,
                                openai::OpenAIProvider, xai::XAIProvider};

        match Provider::from_str(provider_name) {
            Some(Provider::Anthropic) | Some(Provider::AnthropicMax) => {
                let provider = AnthropicProvider::from_config(provider_config)?;
                provider.chat_completion_stream(request).await
            }
            Some(Provider::OpenAI) => {
                let provider = OpenAIProvider::from_config(provider_config)?;
                provider.chat_completion_stream(request).await
            }
            Some(Provider::Xai) => {
                let provider = XAIProvider::from_config(provider_config)?;
                provider.chat_completion_stream(request).await
            }
            Some(Provider::Gemini) => {
                let provider = GeminiProvider::from_config(provider_config)?;
                provider.chat_completion_stream(request).await
            }
            Some(Provider::Ollama) => {
                let provider = OllamaProvider::from_config(provider_config)?;
                provider.chat_completion_stream(request).await
            }
            Some(Provider::GithubCopilot) => {
                let provider = GitHubCopilotProvider::from_config(provider_config)?;
                provider.chat_completion_stream(request).await
            }
            Some(Provider::Omen) => {
                Err(anyhow!("Omen streaming not yet implemented"))
            }
            None => Err(anyhow!("Unknown provider: {}", provider_name)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{ProviderConfig, RoutingConfig, ServerConfig, CacheConfig};
    use crate::types::{AuthMethod, ChatMessage, Role};
    use std::collections::HashMap;

    fn create_test_config() -> Config {
        let mut providers = HashMap::new();

        providers.insert(
            "anthropic".to_string(),
            ProviderConfig {
                enabled: true,
                auth_method: AuthMethod::ApiKey,
                api_key: Some("test-key-1".to_string()),
                base_url: None,
                endpoint: None,
                model: Some("claude-3-5-sonnet-20241022".to_string()),
                max_tokens: None,
                temperature: None,
                client_id: None,
            },
        );

        providers.insert(
            "openai".to_string(),
            ProviderConfig {
                enabled: true,
                auth_method: AuthMethod::ApiKey,
                api_key: Some("test-key-2".to_string()),
                base_url: None,
                endpoint: None,
                model: Some("gpt-4o".to_string()),
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

        Config {
            server: ServerConfig {
                bind: "127.0.0.1:3000".to_string(),
                grpc: "127.0.0.1:50051".to_string(),
                log_level: "info".to_string(),
                uds_path: None,
                uds_enabled: false,
            },
            routing: RoutingConfig {
                strategy: "round-robin".to_string(),
                fallback_chain: vec!["anthropic".to_string(), "openai".to_string()],
                load_balance: vec!["anthropic".to_string(), "openai".to_string()],
            },
            providers,
            models_dev: Default::default(),
            cache: CacheConfig {
                enabled: false,
                ttl: 300,
                max_size: 100,
            },
            rate_limiting: Default::default(),
            metrics: Default::default(),
            oauth: Default::default(),
        }
    }

    fn create_test_request() -> ChatRequest {
        ChatRequest {
            model: "claude-3-5-sonnet-20241022".to_string(),
            messages: vec![ChatMessage {
                role: Role::User,
                content: "Hello, world!".to_string(),
            }],
            stream: false,
            temperature: None,
            max_tokens: None,
            top_p: None,
            system: None,
        }
    }

    #[test]
    fn test_router_creation() {
        let config = Arc::new(create_test_config());
        let router = Router::new(config);

        // Verify initial state
        assert_eq!(router.round_robin_counter.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn test_enabled_providers() {
        let config = Arc::new(create_test_config());
        let enabled = config.enabled_providers();

        // Should have 2 enabled providers
        assert_eq!(enabled.len(), 2);

        // Check that disabled provider is not included
        assert!(!enabled.iter().any(|(name, _)| name == "disabled"));
    }

    #[test]
    fn test_round_robin_counter_increment() {
        let config = Arc::new(create_test_config());
        let router = Router::new(config.clone());
        let providers = config.enabled_providers();
        let provider_count = providers.len();

        // Test that counter increments properly
        for i in 0..10 {
            let expected_index = i % provider_count;
            let index = router.round_robin_counter.load(Ordering::Relaxed) % provider_count;
            assert_eq!(index, expected_index);

            // Increment for next iteration
            router.round_robin_counter.fetch_add(1, Ordering::Relaxed);
        }
    }

    #[test]
    fn test_round_robin_distribution() {
        let config = Arc::new(create_test_config());
        let router = Router::new(config.clone());
        let providers = config.enabled_providers();

        // Simulate multiple requests
        let mut distribution: HashMap<usize, usize> = HashMap::new();

        for _ in 0..100 {
            let index = router.round_robin_counter.fetch_add(1, Ordering::Relaxed) % providers.len();
            *distribution.entry(index).or_insert(0) += 1;
        }

        // Each provider should get roughly equal distribution
        for count in distribution.values() {
            // With 100 requests and 2 providers, each should get ~50
            assert!(*count >= 45 && *count <= 55, "Distribution unbalanced: {}", count);
        }
    }

    #[test]
    fn test_cache_key_generation() {
        let request1 = create_test_request();
        let mut request2 = request1.clone();

        // Same requests should generate same cache key
        let key1 = crate::cache::cache_key(&request1);
        let key2 = crate::cache::cache_key(&request2);
        assert_eq!(key1, key2);

        // Different requests should generate different cache keys
        request2.messages[0].content = "Different message".to_string();
        let key3 = crate::cache::cache_key(&request2);
        assert_ne!(key1, key3);
    }

    #[test]
    fn test_fallback_chain_order() {
        let config = Arc::new(create_test_config());

        // Verify fallback chain is in correct order
        assert_eq!(config.routing.fallback_chain[0], "anthropic");
        assert_eq!(config.routing.fallback_chain[1], "openai");
    }
}

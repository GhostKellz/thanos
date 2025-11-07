/// Models.dev API client for model pricing and metadata
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub id: String,
    pub provider: String,
    pub name: String,
    pub pricing: Option<Pricing>,
    pub context_length: Option<i32>,
    pub output_limit: Option<i32>,
    pub supports_streaming: Option<bool>,
    pub supports_functions: Option<bool>,
    pub supports_vision: Option<bool>,
    pub supports_reasoning: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pricing {
    pub input: f64,  // USD per 1M tokens
    pub output: f64, // USD per 1M tokens
    pub cache_read: Option<f64>, // USD per 1M cached tokens
    pub reasoning: Option<f64>,  // USD per 1M reasoning tokens
}

// models.dev API structures
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct ProviderData {
    id: String,
    name: String,
    models: HashMap<String, ModelData>,
}

#[derive(Debug, Deserialize)]
struct ModelData {
    id: String,
    name: String,
    cost: Option<CostData>,
    limit: Option<LimitData>,
    modalities: Option<Modalities>,
    tool_call: Option<bool>,
    reasoning: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct CostData {
    input: Option<f64>,
    output: Option<f64>,
    cache_read: Option<f64>,
    reasoning: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct LimitData {
    context: Option<i32>,
    output: Option<i32>,
}

#[derive(Debug, Deserialize)]
struct Modalities {
    input: Option<Vec<String>>,
    #[allow(dead_code)]
    output: Option<Vec<String>>,
}

pub struct ModelsDevClient {
    cache: Arc<Mutex<ModelsCache>>,
    base_url: String,
    cache_ttl: Duration,
}

struct ModelsCache {
    models: HashMap<String, ModelInfo>,
    last_update: Instant,
}

impl ModelsDevClient {
    pub fn new(cache_ttl_secs: u64) -> Self {
        Self {
            cache: Arc::new(Mutex::new(ModelsCache {
                models: HashMap::new(),
                last_update: Instant::now() - Duration::from_secs(cache_ttl_secs + 1),
            })),
            base_url: "https://models.dev/api.json".to_string(),
            cache_ttl: Duration::from_secs(cache_ttl_secs),
        }
    }

    /// Fetch model data from models.dev
    pub async fn fetch_models(&self) -> Result<()> {
        let client = reqwest::Client::new();
        let response = client.get(&self.base_url).send().await?;

        if !response.status().is_success() {
            anyhow::bail!("Failed to fetch models.dev data: {}", response.status());
        }

        // Parse the API response - it's a map of provider_id -> ProviderData
        let providers: HashMap<String, ProviderData> = response.json().await?;

        let mut models = HashMap::new();

        // Iterate through providers and their models
        for (provider_id, provider_data) in providers {
            for (_model_key, model_data) in provider_data.models {
                let model_id = model_data.id.clone();

                // Check for vision support (image in input modalities)
                let supports_vision = model_data
                    .modalities
                    .as_ref()
                    .and_then(|m| m.input.as_ref())
                    .map(|inputs| inputs.contains(&"image".to_string()))
                    .unwrap_or(false);

                let model_info = ModelInfo {
                    id: model_id.clone(),
                    provider: provider_id.clone(),
                    name: model_data.name,
                    pricing: model_data.cost.map(|cost| Pricing {
                        input: cost.input.unwrap_or(0.0),
                        output: cost.output.unwrap_or(0.0),
                        cache_read: cost.cache_read,
                        reasoning: cost.reasoning,
                    }),
                    context_length: model_data.limit.as_ref().and_then(|l| l.context),
                    output_limit: model_data.limit.as_ref().and_then(|l| l.output),
                    supports_streaming: Some(true), // Most models support streaming
                    supports_functions: model_data.tool_call,
                    supports_vision: Some(supports_vision),
                    supports_reasoning: model_data.reasoning,
                };

                models.insert(model_id, model_info);
            }
        }

        tracing::info!("Loaded {} models from models.dev", models.len());

        // Update cache
        let mut cache = self.cache.lock().unwrap();
        cache.models = models;
        cache.last_update = Instant::now();

        Ok(())
    }

    /// Get model info from cache, refreshing if needed
    pub async fn get_model_info(&self, model_id: &str) -> Option<ModelInfo> {
        // Check if cache needs refresh
        {
            let cache = self.cache.lock().unwrap();
            if cache.last_update.elapsed() < self.cache_ttl {
                return cache.models.get(model_id).cloned();
            }
        }

        // Cache expired, refresh
        if let Err(e) = self.fetch_models().await {
            tracing::warn!("Failed to refresh models.dev cache: {}", e);
        }

        // Return from refreshed cache
        let cache = self.cache.lock().unwrap();
        cache.models.get(model_id).cloned()
    }

    /// Calculate cost for token usage
    pub async fn calculate_cost(
        &self,
        model_id: &str,
        input_tokens: i32,
        output_tokens: i32,
    ) -> Option<f64> {
        let model_info = self.get_model_info(model_id).await?;
        let pricing = model_info.pricing?;

        // Convert tokens to millions and calculate cost
        let input_cost = (input_tokens as f64 / 1_000_000.0) * pricing.input;
        let output_cost = (output_tokens as f64 / 1_000_000.0) * pricing.output;

        Some(input_cost + output_cost)
    }

    /// Get all cached models
    pub fn get_all_models(&self) -> Vec<ModelInfo> {
        let cache = self.cache.lock().unwrap();
        cache.models.values().cloned().collect()
    }
}

/// Global models.dev client
pub static MODELS_DEV_CLIENT: once_cell::sync::Lazy<ModelsDevClient> =
    once_cell::sync::Lazy::new(|| ModelsDevClient::new(3600)); // 1 hour cache

/// Well-known model pricing (fallback when models.dev is unavailable)
pub fn get_fallback_pricing(model_id: &str) -> Option<Pricing> {
    match model_id {
        // Anthropic Claude
        "claude-opus-4-20250514" => Some(Pricing {
            input: 15.0,
            output: 75.0,
            cache_read: Some(1.5),
            reasoning: None,
        }),
        "claude-sonnet-4-5-20250513" => Some(Pricing {
            input: 3.0,
            output: 15.0,
            cache_read: Some(0.3),
            reasoning: None,
        }),
        "claude-haiku-4-5-20250513" => Some(Pricing {
            input: 0.25,
            output: 1.25,
            cache_read: Some(0.025),
            reasoning: None,
        }),
        // OpenAI
        "gpt-5" => Some(Pricing {
            input: 10.0,
            output: 30.0,
            cache_read: None,
            reasoning: None,
        }),
        "gpt-4o" => Some(Pricing {
            input: 5.0,
            output: 15.0,
            cache_read: Some(2.5),
            reasoning: None,
        }),
        "o3-mini" => Some(Pricing {
            input: 1.0,
            output: 4.0,
            cache_read: None,
            reasoning: Some(8.0),
        }),
        // Google Gemini
        "gemini-2.5-pro" => Some(Pricing {
            input: 1.25,
            output: 5.0,
            cache_read: None,
            reasoning: None,
        }),
        "gemini-2.0-flash-exp" => Some(Pricing {
            input: 0.075,
            output: 0.3,
            cache_read: None,
            reasoning: None,
        }),
        // xAI Grok
        "grok-2-latest" => Some(Pricing {
            input: 2.0,
            output: 10.0,
            cache_read: None,
            reasoning: None,
        }),
        _ => None,
    }
}

/// Calculate cost with fallback to hardcoded pricing
pub async fn calculate_cost_with_fallback(
    model_id: &str,
    input_tokens: i32,
    output_tokens: i32,
) -> Option<f64> {
    // Try models.dev first
    if let Some(cost) = MODELS_DEV_CLIENT.calculate_cost(model_id, input_tokens, output_tokens).await {
        return Some(cost);
    }

    // Fallback to hardcoded pricing
    let pricing = get_fallback_pricing(model_id)?;
    let input_cost = (input_tokens as f64 / 1_000_000.0) * pricing.input;
    let output_cost = (output_tokens as f64 / 1_000_000.0) * pricing.output;

    Some(input_cost + output_cost)
}

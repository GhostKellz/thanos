use prometheus::{
    Counter, CounterVec, Gauge, GaugeVec, HistogramOpts, HistogramVec, Opts, Registry,
};
use std::sync::Arc;

/// Global metrics for Thanos
pub struct Metrics {
    pub registry: Registry,

    // Request metrics
    pub requests_total: CounterVec,
    pub request_duration_seconds: HistogramVec,
    pub requests_in_flight: GaugeVec,

    // Provider metrics
    pub provider_requests_total: CounterVec,
    pub provider_errors_total: CounterVec,
    pub provider_duration_seconds: HistogramVec,

    // Token metrics
    pub tokens_used_total: CounterVec,
    pub estimated_cost_usd: CounterVec,

    // Cache metrics
    pub cache_hits_total: Counter,
    pub cache_misses_total: Counter,
    pub cache_size: Gauge,

    // Rate limiting metrics
    pub rate_limit_exceeded_total: CounterVec,

    // Circuit breaker metrics
    pub circuit_breaker_state: GaugeVec, // 0 = closed, 1 = open, 2 = half-open
    pub circuit_breaker_failures: CounterVec,
}

impl Metrics {
    pub fn new() -> anyhow::Result<Self> {
        let registry = Registry::new();

        // Request metrics
        let requests_total = CounterVec::new(
            Opts::new("thanos_requests_total", "Total number of requests"),
            &["endpoint", "method", "status"],
        )?;

        let request_duration_seconds = HistogramVec::new(
            HistogramOpts::new(
                "thanos_request_duration_seconds",
                "Request duration in seconds",
            )
            .buckets(vec![0.001, 0.01, 0.1, 0.5, 1.0, 2.5, 5.0, 10.0]),
            &["endpoint", "method"],
        )?;

        let requests_in_flight = GaugeVec::new(
            Opts::new(
                "thanos_requests_in_flight",
                "Number of requests currently being processed",
            ),
            &["endpoint"],
        )?;

        // Provider metrics
        let provider_requests_total = CounterVec::new(
            Opts::new(
                "thanos_provider_requests_total",
                "Total number of requests to each provider",
            ),
            &["provider", "model", "status"],
        )?;

        let provider_errors_total = CounterVec::new(
            Opts::new(
                "thanos_provider_errors_total",
                "Total number of errors from each provider",
            ),
            &["provider", "error_type"],
        )?;

        let provider_duration_seconds = HistogramVec::new(
            HistogramOpts::new(
                "thanos_provider_duration_seconds",
                "Provider API call duration in seconds",
            )
            .buckets(vec![0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]),
            &["provider", "model"],
        )?;

        // Token metrics
        let tokens_used_total = CounterVec::new(
            Opts::new(
                "thanos_tokens_used_total",
                "Total tokens used (input + output)",
            ),
            &["provider", "model", "token_type"], // token_type: input, output
        )?;

        let estimated_cost_usd = CounterVec::new(
            Opts::new(
                "thanos_estimated_cost_usd",
                "Estimated cost in USD based on token usage",
            ),
            &["provider", "model"],
        )?;

        // Cache metrics
        let cache_hits_total = Counter::new(
            "thanos_cache_hits_total",
            "Total number of cache hits",
        )?;

        let cache_misses_total = Counter::new(
            "thanos_cache_misses_total",
            "Total number of cache misses",
        )?;

        let cache_size = Gauge::new(
            "thanos_cache_size",
            "Current number of items in cache",
        )?;

        // Rate limiting metrics
        let rate_limit_exceeded_total = CounterVec::new(
            Opts::new(
                "thanos_rate_limit_exceeded_total",
                "Total number of requests rejected due to rate limiting",
            ),
            &["endpoint"],
        )?;

        // Circuit breaker metrics
        let circuit_breaker_state = GaugeVec::new(
            Opts::new(
                "thanos_circuit_breaker_state",
                "Circuit breaker state (0=closed, 1=open, 2=half-open)",
            ),
            &["provider"],
        )?;

        let circuit_breaker_failures = CounterVec::new(
            Opts::new(
                "thanos_circuit_breaker_failures_total",
                "Total number of circuit breaker failures",
            ),
            &["provider"],
        )?;

        // Register all metrics
        registry.register(Box::new(requests_total.clone()))?;
        registry.register(Box::new(request_duration_seconds.clone()))?;
        registry.register(Box::new(requests_in_flight.clone()))?;
        registry.register(Box::new(provider_requests_total.clone()))?;
        registry.register(Box::new(provider_errors_total.clone()))?;
        registry.register(Box::new(provider_duration_seconds.clone()))?;
        registry.register(Box::new(tokens_used_total.clone()))?;
        registry.register(Box::new(estimated_cost_usd.clone()))?;
        registry.register(Box::new(cache_hits_total.clone()))?;
        registry.register(Box::new(cache_misses_total.clone()))?;
        registry.register(Box::new(cache_size.clone()))?;
        registry.register(Box::new(rate_limit_exceeded_total.clone()))?;
        registry.register(Box::new(circuit_breaker_state.clone()))?;
        registry.register(Box::new(circuit_breaker_failures.clone()))?;

        Ok(Self {
            registry,
            requests_total,
            request_duration_seconds,
            requests_in_flight,
            provider_requests_total,
            provider_errors_total,
            provider_duration_seconds,
            tokens_used_total,
            estimated_cost_usd,
            cache_hits_total,
            cache_misses_total,
            cache_size,
            rate_limit_exceeded_total,
            circuit_breaker_state,
            circuit_breaker_failures,
        })
    }
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new().expect("Failed to create metrics")
    }
}

/// Global metrics instance
pub static METRICS: once_cell::sync::Lazy<Arc<Metrics>> =
    once_cell::sync::Lazy::new(|| Arc::new(Metrics::default()));

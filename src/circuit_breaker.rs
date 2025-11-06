/// Circuit breaker implementation for provider resilience
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CircuitState {
    Closed,     // Normal operation
    Open,       // Failing, reject requests
    HalfOpen,   // Testing if service recovered
}

pub struct CircuitBreaker {
    providers: Arc<Mutex<HashMap<String, ProviderCircuit>>>,
    failure_threshold: u32,
    success_threshold: u32,
    timeout: Duration,
}

struct ProviderCircuit {
    state: CircuitState,
    failures: u32,
    successes: u32,
    last_failure_time: Option<Instant>,
    next_attempt: Option<Instant>,
}

impl CircuitBreaker {
    pub fn new(failure_threshold: u32, success_threshold: u32, timeout_secs: u64) -> Self {
        Self {
            providers: Arc::new(Mutex::new(HashMap::new())),
            failure_threshold,
            success_threshold,
            timeout: Duration::from_secs(timeout_secs),
        }
    }

    pub fn can_attempt(&self, provider: &str) -> bool {
        let mut providers = self.providers.lock().unwrap();
        let circuit = providers.entry(provider.to_string()).or_insert_with(|| ProviderCircuit {
            state: CircuitState::Closed,
            failures: 0,
            successes: 0,
            last_failure_time: None,
            next_attempt: None,
        });

        let now = Instant::now();

        match circuit.state {
            CircuitState::Closed => true,
            CircuitState::Open => {
                if let Some(next_attempt) = circuit.next_attempt {
                    if now >= next_attempt {
                        circuit.state = CircuitState::HalfOpen;
                        circuit.successes = 0;
                        true
                    } else {
                        false
                    }
                } else {
                    false
                }
            }
            CircuitState::HalfOpen => true,
        }
    }

    pub fn record_success(&self, provider: &str) {
        let mut providers = self.providers.lock().unwrap();
        if let Some(circuit) = providers.get_mut(provider) {
            match circuit.state {
                CircuitState::Closed => {
                    circuit.failures = 0;
                }
                CircuitState::HalfOpen => {
                    circuit.successes += 1;
                    if circuit.successes >= self.success_threshold {
                        circuit.state = CircuitState::Closed;
                        circuit.failures = 0;
                        circuit.successes = 0;
                    }
                }
                CircuitState::Open => {}
            }
        }
    }

    pub fn record_failure(&self, provider: &str) {
        let mut providers = self.providers.lock().unwrap();
        let circuit = providers.entry(provider.to_string()).or_insert_with(|| ProviderCircuit {
            state: CircuitState::Closed,
            failures: 0,
            successes: 0,
            last_failure_time: None,
            next_attempt: None,
        });

        let now = Instant::now();
        circuit.last_failure_time = Some(now);

        match circuit.state {
            CircuitState::Closed => {
                circuit.failures += 1;
                if circuit.failures >= self.failure_threshold {
                    circuit.state = CircuitState::Open;
                    circuit.next_attempt = Some(now + self.timeout);

                    // Record in metrics
                    crate::metrics::METRICS.circuit_breaker_state
                        .with_label_values(&[provider])
                        .set(1.0); // Open
                    crate::metrics::METRICS.circuit_breaker_failures
                        .with_label_values(&[provider])
                        .inc();
                }
            }
            CircuitState::HalfOpen => {
                circuit.state = CircuitState::Open;
                circuit.next_attempt = Some(now + self.timeout);

                crate::metrics::METRICS.circuit_breaker_state
                    .with_label_values(&[provider])
                    .set(1.0); // Open
            }
            CircuitState::Open => {}
        }
    }

    pub fn get_state(&self, provider: &str) -> CircuitState {
        let providers = self.providers.lock().unwrap();
        providers.get(provider).map(|c| c.state).unwrap_or(CircuitState::Closed)
    }
}

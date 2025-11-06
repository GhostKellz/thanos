/// Simple token bucket rate limiter
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Clone)]
pub struct RateLimiter {
    buckets: Arc<Mutex<HashMap<String, TokenBucket>>>,
    requests_per_minute: u32,
    requests_per_hour: u32,
}

struct TokenBucket {
    tokens: f64,
    last_refill: Instant,
    hourly_count: u32,
    hourly_reset: Instant,
}

impl RateLimiter {
    pub fn new(requests_per_minute: u32, requests_per_hour: u32) -> Self {
        Self {
            buckets: Arc::new(Mutex::new(HashMap::new())),
            requests_per_minute,
            requests_per_hour,
        }
    }

    pub fn check_rate_limit(&self, key: &str) -> bool {
        let mut buckets = self.buckets.lock().unwrap();
        let now = Instant::now();

        let bucket = buckets.entry(key.to_string()).or_insert_with(|| TokenBucket {
            tokens: self.requests_per_minute as f64,
            last_refill: now,
            hourly_count: 0,
            hourly_reset: now + Duration::from_secs(3600),
        });

        // Reset hourly counter
        if now >= bucket.hourly_reset {
            bucket.hourly_count = 0;
            bucket.hourly_reset = now + Duration::from_secs(3600);
        }

        // Check hourly limit
        if bucket.hourly_count >= self.requests_per_hour {
            return false;
        }

        // Refill tokens based on time passed
        let elapsed = now.duration_since(bucket.last_refill).as_secs_f64();
        let refill_rate = self.requests_per_minute as f64 / 60.0; // tokens per second
        bucket.tokens = (bucket.tokens + elapsed * refill_rate).min(self.requests_per_minute as f64);
        bucket.last_refill = now;

        // Check if we have enough tokens
        if bucket.tokens >= 1.0 {
            bucket.tokens -= 1.0;
            bucket.hourly_count += 1;
            true
        } else {
            false
        }
    }
}

/// Simple LRU cache for responses
use crate::types::ChatResponse;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub struct ResponseCache {
    entries: Arc<Mutex<HashMap<String, CacheEntry>>>,
    max_size: usize,
    ttl: Duration,
}

struct CacheEntry {
    response: ChatResponse,
    created_at: Instant,
    access_count: u64,
}

impl ResponseCache {
    pub fn new(max_size: usize, ttl_secs: u64) -> Self {
        Self {
            entries: Arc::new(Mutex::new(HashMap::new())),
            max_size,
            ttl: Duration::from_secs(ttl_secs),
        }
    }

    pub fn get(&self, key: &str) -> Option<ChatResponse> {
        let mut entries = self.entries.lock().unwrap();

        if let Some(entry) = entries.get_mut(key) {
            let now = Instant::now();

            // Check if expired
            if now.duration_since(entry.created_at) > self.ttl {
                entries.remove(key);
                crate::metrics::METRICS.cache_misses_total.inc();
                return None;
            }

            // Update access count
            entry.access_count += 1;

            // Record cache hit
            crate::metrics::METRICS.cache_hits_total.inc();

            Some(entry.response.clone())
        } else {
            // Record cache miss
            crate::metrics::METRICS.cache_misses_total.inc();
            None
        }
    }

    pub fn set(&self, key: String, response: ChatResponse) {
        let mut entries = self.entries.lock().unwrap();

        // Evict if at capacity (simple LRU: remove oldest by creation time)
        if entries.len() >= self.max_size && !entries.contains_key(&key) {
            if let Some(oldest_key) = entries
                .iter()
                .min_by_key(|(_, entry)| entry.created_at)
                .map(|(k, _)| k.clone())
            {
                entries.remove(&oldest_key);
            }
        }

        entries.insert(key, CacheEntry {
            response,
            created_at: Instant::now(),
            access_count: 0,
        });

        // Update cache size metric
        crate::metrics::METRICS.cache_size.set(entries.len() as f64);
    }

    pub fn clear(&self) {
        let mut entries = self.entries.lock().unwrap();
        entries.clear();
        crate::metrics::METRICS.cache_size.set(0.0);
    }

    pub fn size(&self) -> usize {
        self.entries.lock().unwrap().len()
    }
}

/// Generate cache key from request
pub fn cache_key(request: &crate::types::ChatRequest) -> String {
    use sha2::{Digest, Sha256};

    let mut hasher = Sha256::new();
    hasher.update(request.model.as_bytes());
    for msg in &request.messages {
        hasher.update(format!("{:?}:{}", msg.role, msg.content).as_bytes());
    }
    if let Some(temp) = request.temperature {
        hasher.update(temp.to_string().as_bytes());
    }
    if let Some(max_tokens) = request.max_tokens {
        hasher.update(max_tokens.to_string().as_bytes());
    }

    format!("{:x}", hasher.finalize())
}

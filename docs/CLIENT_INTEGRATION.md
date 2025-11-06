# Thanos Client Integration Guide

For **zeke** and **zeke.nvim** integration

---

## Quick Start

**Thanos runs on:**
- HTTP: `http://localhost:9000`
- gRPC: `localhost:50051`
- Unix Socket: `/tmp/thanos.sock` (fastest for local clients)

**Start Thanos:**
```bash
cargo run --bin thanos
# or
./target/release/thanos
```

---

## API Endpoints for Zeke

### 1. Health Check
```bash
GET /health
```

### 2. List Available Providers
```bash
GET /v1/providers
```

### 3. Chat Completion (OpenAI-compatible)
```bash
POST /v1/chat/completions
```

**Request:**
```json
{
  "model": "gemini-2.5-pro",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": false
}
```

### 4. List Models
```bash
GET /v1/models
```

---

## Rust Client Example (for zeke)

```rust
use reqwest::Client;
use serde_json::json;

let response = client
    .post("http://localhost:9000/v1/chat/completions")
    .json(&json!({
        "model": "gemini-2.5-pro",
        "messages": [{"role": "user", "content": "Hello"}]
    }))
    .send()
    .await?
    .json::<serde_json::Value>()
    .await?;
```

---

## Configuration

Edit `config.toml`:

```toml
[providers.gemini]
enabled = true
api_key = "${GEMINI_API_KEY}"
model = "gemini-2.5-pro"
```

**OAuth:**
```bash
thanos auth claude      # Claude Max
thanos auth github      # GitHub Copilot
```

---

## Testing

```bash
./test_all_endpoints.sh
```

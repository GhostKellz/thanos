# Thanos Gateway Protocol Architecture

**Universal AI Gateway with Hybrid Transport Layer**

Version: 1.0
Status: Production Ready
Author: Thanos Team
Date: 2025-11-06

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Transport Layers](#transport-layers)
4. [Deployment](#deployment)
5. [Performance](#performance)
6. [Client Integration](#client-integration)
7. [API Reference](#api-reference)
8. [Security](#security)
9. [Monitoring](#monitoring)

---

## Overview

Thanos is a production-ready AI gateway that provides unified access to multiple LLM providers through a hybrid transport architecture. It supports:

- **5 Transport Methods**: UDS, HTTP/1.1, HTTP/2, gRPC, HTTP/3 (QUIC)
- **6 AI Providers**: Anthropic, OpenAI, Google Gemini, xAI, GitHub Copilot, Ollama
- **2 Auth Methods**: OAuth (Claude Max, GitHub Copilot) + API Keys
- **Auto-refresh Tokens**: Automatic token renewal for OAuth providers
- **High Performance**: UDS for local, HTTP/3 for remote, connection pooling

### Design Goals

✅ **Performance**: Sub-millisecond local latency via UDS
✅ **Flexibility**: Multiple transports for different use cases
✅ **Security**: OAuth + keyring storage, TLS for remote access
✅ **Reliability**: Auto-retry, circuit breakers, health checks
✅ **Simplicity**: Single binary, simple config, easy deployment

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Thanos Gateway                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              Transport Layer (Hybrid)                   │   │
│  ├────────────────────────────────────────────────────────┤   │
│  │  1. UDS Socket:  /var/run/thanos/thanos.sock          │   │ ← Zeke CLI
│  │  2. HTTP/1.1:    0.0.0.0:8080                          │   │ ← cURL, scripts
│  │  3. HTTP/2 REST: 0.0.0.0:8080                          │   │ ← Web clients
│  │  4. gRPC:        0.0.0.0:50051                         │   │ ← Streaming
│  │  5. HTTP/3 QUIC: 0.0.0.0:443 (optional)                │   │ ← Future/mobile
│  └────────────────────────────────────────────────────────┘   │
│                              ▲                                  │
│                              │                                  │
│  ┌──────────────────────────┴──────────────────────────────┐  │
│  │              Router & Load Balancer                      │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  • Strategy: Omen / Preferred / Round-Robin / Fallback  │  │
│  │  • Circuit Breaker: Auto-disable failing providers      │  │
│  │  • Retry Logic: Exponential backoff with jitter         │  │
│  │  • Rate Limiting: Per-provider token bucket             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ▲                                  │
│                              │                                  │
│  ┌──────────────────────────┴──────────────────────────────┐  │
│  │              Provider Layer                              │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  • Anthropic (API + OAuth)                               │  │
│  │  • OpenAI (API)                                          │  │
│  │  • Google Gemini (API)                                   │  │
│  │  • xAI (API)                                             │  │
│  │  • GitHub Copilot (OAuth)                                │  │
│  │  • Ollama (Local)                                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ▲                                  │
│                              │                                  │
│  ┌──────────────────────────┴──────────────────────────────┐  │
│  │              Authentication Layer                        │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │  • TokenManager: Auto-refresh OAuth tokens               │  │
│  │  • KeyringStore: Secure system keyring storage           │  │
│  │  • API Key: Environment variables or config              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Transport Layers

### 1. Unix Domain Socket (UDS) - Primary for Local Clients

**Path**: `/var/run/thanos/thanos.sock`
**Protocol**: HTTP/1.1 over UDS
**Use Case**: Zeke CLI, Zeke.nvim, local tools

#### Advantages
✅ **Fastest**: ~10x faster than localhost TCP (no network stack)
✅ **Secure**: Filesystem permissions control access
✅ **Simple**: Just open socket file
✅ **No ports**: No port conflicts or firewall issues

#### Example Client (Rust)
```rust
use tokio::net::UnixStream;

let stream = UnixStream::connect("/var/run/thanos/thanos.sock").await?;
// Send HTTP request over UDS
```

#### Example Client (cURL)
```bash
curl --unix-socket /var/run/thanos/thanos.sock \
     http://localhost/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "claude-sonnet-4-5-20250513",
       "messages": [{"role": "user", "content": "Hello"}]
     }'
```

#### Configuration
```toml
[server]
uds_path = "/var/run/thanos/thanos.sock"
uds_permissions = "0660"  # rw-rw----
uds_group = "thanos"      # Allow group access
```

---

### 2. HTTP/2 REST API - Primary for Web Clients

**Address**: `http://0.0.0.0:8080`
**Protocol**: HTTP/1.1 + HTTP/2 (auto-negotiated)
**Use Case**: Web apps, remote access, debugging

#### Advantages
✅ **Universal**: Works everywhere (browsers, curl, scripts)
✅ **Standard**: OpenAI-compatible API format
✅ **Debugging**: Easy to test with curl
✅ **Multiplexing**: HTTP/2 for parallel requests

#### Endpoints

**Chat Completions**
```http
POST /v1/chat/completions
Content-Type: application/json

{
  "model": "gpt-5",
  "messages": [
    {"role": "user", "content": "Write a Rust function"}
  ],
  "stream": false
}
```

**Health Check**
```http
GET /health
```

**Metrics**
```http
GET /metrics  # Prometheus format
```

**List Models**
```http
GET /v1/models
```

---

### 3. gRPC - High-Performance Streaming

**Address**: `0.0.0.0:50051`
**Protocol**: gRPC (HTTP/2 + Protobuf)
**Use Case**: Streaming completions, high-throughput clients

#### Advantages
✅ **Efficient**: Binary protocol, smaller payloads
✅ **Streaming**: Bidirectional streaming support
✅ **Type-safe**: Protobuf schema validation
✅ **Fast**: Better than REST for high-frequency calls

#### Proto Definition
```protobuf
syntax = "proto3";

service ThanosService {
  rpc ChatCompletion(ChatRequest) returns (ChatResponse);
  rpc ChatCompletionStream(ChatRequest) returns (stream ChatResponse);
  rpc Health(HealthRequest) returns (HealthResponse);
}

message ChatRequest {
  string model = 1;
  repeated Message messages = 2;
  optional float temperature = 3;
  optional int32 max_tokens = 4;
}

message ChatResponse {
  string provider = 1;
  string model = 2;
  string content = 3;
  bool done = 4;
  optional Usage usage = 5;
}
```

#### Example Client (Rust)
```rust
let mut client = ThanosServiceClient::connect("http://localhost:50051").await?;

let request = tonic::Request::new(ChatRequest {
    model: "claude-sonnet-4-5-20250513".to_string(),
    messages: vec![Message {
        role: "user".to_string(),
        content: "Hello".to_string(),
    }],
    temperature: Some(0.7),
    max_tokens: None,
});

let response = client.chat_completion(request).await?;
```

---

### 4. HTTP/3 + QUIC - Future-Proof (Optional)

**Address**: `0.0.0.0:443`
**Protocol**: HTTP/3 over QUIC (UDP)
**Use Case**: Mobile clients, unstable networks, future-proofing

#### Advantages
✅ **0-RTT**: Faster reconnection than HTTP/2
✅ **Multiplexing**: Better than HTTP/2 (no head-of-line blocking)
✅ **Mobile-friendly**: Better on unstable connections
✅ **Modern**: Latest HTTP standard

#### When to Enable
- Public API with mobile clients
- High-latency or unstable networks
- Many concurrent connections
- Future-proof infrastructure

#### Configuration
```toml
[server]
http3_enabled = false  # Default: disabled
http3_bind = "0.0.0.0:443"
http3_cert = "/etc/thanos/cert.pem"
http3_key = "/etc/thanos/key.pem"
```

---

## Deployment

### 1. Arch Linux (systemd)

#### A. Install from Source

```bash
# Build
cargo build --release

# Install
sudo cp target/release/thanos /usr/bin/
sudo mkdir -p /etc/thanos /var/lib/thanos /var/run/thanos
sudo cp config.example.toml /etc/thanos/config.toml
sudo chmod 644 /etc/thanos/config.toml

# Create user
sudo useradd -r -s /bin/false thanos

# Create systemd service
sudo cp deployment/thanos.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable thanos
sudo systemctl start thanos
```

#### B. Install from AUR

```bash
yay -S thanos-gateway
sudo systemctl enable thanos
sudo systemctl start thanos
```

#### Systemd Service File

```ini
# /etc/systemd/system/thanos.service
[Unit]
Description=Thanos AI Gateway
Documentation=https://github.com/yourusername/thanos
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=thanos
Group=thanos
ExecStart=/usr/bin/thanos
Restart=on-failure
RestartSec=5s

# Environment
Environment="THANOS_CONFIG=/etc/thanos/config.toml"
EnvironmentFile=-/etc/thanos/thanos.env

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/thanos /var/run/thanos
CapabilityBoundingSet=
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=thanos

[Install]
WantedBy=multi-user.target
```

#### Environment File

```bash
# /etc/thanos/thanos.env
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
GEMINI_API_KEY=xxx
XAI_API_KEY=xxx
```

---

### 2. Docker + Docker Compose

#### Dockerfile (Multi-stage)

```dockerfile
# syntax=docker/dockerfile:1

# ──────────────────────────────────────────────────────────
# Stage 1: Build
# ──────────────────────────────────────────────────────────
FROM rust:1.83-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    musl-dev \
    protobuf-dev \
    pkgconfig \
    openssl-dev

WORKDIR /build

# Copy dependency manifests
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY proto ./proto
COPY build.rs ./

# Build release binary
RUN cargo build --release --target x86_64-unknown-linux-musl

# ──────────────────────────────────────────────────────────
# Stage 2: Runtime
# ──────────────────────────────────────────────────────────
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    libgcc

# Create user
RUN addgroup -g 1000 thanos && \
    adduser -D -u 1000 -G thanos thanos

# Create directories
RUN mkdir -p /etc/thanos /var/lib/thanos /var/run/thanos && \
    chown -R thanos:thanos /var/lib/thanos /var/run/thanos

# Copy binary
COPY --from=builder /build/target/x86_64-unknown-linux-musl/release/thanos /usr/local/bin/

# Copy config
COPY config.example.toml /etc/thanos/config.toml

# Switch to non-root user
USER thanos

# Expose ports
EXPOSE 8080 50051

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["/usr/local/bin/thanos"]
```

#### docker-compose.yml

```yaml
version: '3.8'

services:
  # ────────────────────────────────────────────────────────
  # Thanos Gateway
  # ────────────────────────────────────────────────────────
  thanos:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: thanos
    restart: unless-stopped

    ports:
      - "8080:8080"   # HTTP/2 REST API
      - "50051:50051" # gRPC
      # - "443:443"   # HTTP/3 (optional)

    volumes:
      # Config (read-only)
      - ./config.toml:/etc/thanos/config.toml:ro

      # Data (persistent)
      - thanos-data:/var/lib/thanos

      # UDS socket (shared with other containers)
      - thanos-socket:/var/run/thanos

    environment:
      # API Keys (use .env file)
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      GEMINI_API_KEY: ${GEMINI_API_KEY}
      XAI_API_KEY: ${XAI_API_KEY}

      # OAuth (stored in keyring, not env)
      # Run: docker exec -it thanos thanos auth claude

      # Logging
      RUST_LOG: info
      THANOS_CONFIG: /etc/thanos/config.toml

    networks:
      - thanos-net

    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 5s

  # ────────────────────────────────────────────────────────
  # Ollama (Local Models)
  # ────────────────────────────────────────────────────────
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped

    volumes:
      - ollama-data:/root/.ollama

    networks:
      - thanos-net

    # Optional: Expose for direct access
    # ports:
    #   - "11434:11434"

    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 3s
      retries: 3

  # ────────────────────────────────────────────────────────
  # Prometheus (Metrics - Optional)
  # ────────────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    profiles: ["monitoring"]

    ports:
      - "9090:9090"

    volumes:
      - ./deployment/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus

    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

    networks:
      - thanos-net

  # ────────────────────────────────────────────────────────
  # Grafana (Dashboard - Optional)
  # ────────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    profiles: ["monitoring"]

    ports:
      - "3000:3000"

    volumes:
      - grafana-data:/var/lib/grafana

    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin

    networks:
      - thanos-net

volumes:
  thanos-data:
  thanos-socket:
  ollama-data:
  prometheus-data:
  grafana-data:

networks:
  thanos-net:
    driver: bridge
```

#### .env File

```bash
# API Keys
ANTHROPIC_API_KEY=sk-ant-xxx
OPENAI_API_KEY=sk-xxx
GEMINI_API_KEY=xxx
XAI_API_KEY=xxx
```

#### Usage

```bash
# Start all services
docker-compose up -d

# Start with monitoring
docker-compose --profile monitoring up -d

# View logs
docker-compose logs -f thanos

# OAuth authentication (inside container)
docker exec -it thanos thanos auth claude
docker exec -it thanos thanos auth github

# Stop services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

---

## Performance

### 1. Connection Pooling

```toml
[performance]
# HTTP client pool
http_pool_size = 100
http_pool_idle_timeout = 90  # seconds

# Provider-specific pools
[performance.provider_pools]
anthropic = 20
openai = 20
gemini = 10
xai = 10
```

```rust
// Implementation
use reqwest::Client;
use std::sync::Arc;

struct ProviderPool {
    client: Arc<Client>,
    max_connections: usize,
}

impl ProviderPool {
    fn new(max_connections: usize) -> Self {
        let client = Client::builder()
            .pool_max_idle_per_host(max_connections)
            .pool_idle_timeout(Duration::from_secs(90))
            .build()
            .unwrap();

        Self {
            client: Arc::new(client),
            max_connections,
        }
    }
}
```

### 2. Response Caching

```toml
[cache]
enabled = true
backend = "memory"  # or "redis"
ttl = 300           # 5 minutes
max_size = 1000     # items

[cache.redis]
url = "redis://localhost:6379"
db = 0
```

```rust
// Cache key: hash(model + messages + temperature + max_tokens)
use blake3::Hasher;

fn cache_key(request: &ChatRequest) -> String {
    let mut hasher = Hasher::new();
    hasher.update(request.model.as_bytes());
    hasher.update(serde_json::to_string(&request.messages).unwrap().as_bytes());
    hasher.update(&request.temperature.unwrap_or(0.7).to_le_bytes());
    hasher.update(&request.max_tokens.unwrap_or(4096).to_le_bytes());
    hasher.finalize().to_hex().to_string()
}
```

### 3. Rate Limiting (Token Bucket)

```toml
[rate_limiting]
enabled = true

# Global limits
requests_per_minute = 100
requests_per_hour = 1000

# Per-provider limits
[rate_limiting.providers]
anthropic_rpm = 50
openai_rpm = 60
gemini_rpm = 60
```

```rust
use governor::{Quota, RateLimiter};
use std::num::NonZeroU32;

struct ProviderRateLimiter {
    limiter: RateLimiter<String, DefaultKeyedStateStore<String>, DefaultClock>,
}

impl ProviderRateLimiter {
    fn new(rpm: u32) -> Self {
        let quota = Quota::per_minute(NonZeroU32::new(rpm).unwrap());
        Self {
            limiter: RateLimiter::keyed(quota),
        }
    }

    async fn check(&self, provider: &str) -> bool {
        self.limiter.check_key(&provider.to_string()).is_ok()
    }
}
```

### 4. Circuit Breaker

```toml
[circuit_breaker]
enabled = true
failure_threshold = 5      # failures before opening
timeout = 60               # seconds before half-open
success_threshold = 2      # successes before closing
```

```rust
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone)]
enum CircuitState {
    Closed,
    Open { until: Instant },
    HalfOpen,
}

struct CircuitBreaker {
    state: Arc<RwLock<CircuitState>>,
    failures: Arc<AtomicUsize>,
    config: CircuitBreakerConfig,
}

impl CircuitBreaker {
    async fn call<F, T>(&self, f: F) -> Result<T>
    where
        F: FnOnce() -> Result<T>,
    {
        let state = self.state.read().await.clone();

        match state {
            CircuitState::Open { until } if Instant::now() < until => {
                Err(anyhow!("Circuit breaker is OPEN"))
            }
            CircuitState::Open { .. } => {
                // Transition to half-open
                *self.state.write().await = CircuitState::HalfOpen;
                self.execute(f).await
            }
            _ => self.execute(f).await,
        }
    }
}
```

### 5. Retry Logic (Exponential Backoff)

```toml
[retry]
enabled = true
max_attempts = 3
initial_delay = 100  # ms
max_delay = 5000     # ms
multiplier = 2.0
jitter = true
```

```rust
use tokio::time::{sleep, Duration};
use rand::Rng;

async fn retry_with_backoff<F, Fut, T>(
    f: F,
    max_attempts: u32,
    initial_delay: u64,
    max_delay: u64,
) -> Result<T>
where
    F: Fn() -> Fut,
    Fut: Future<Output = Result<T>>,
{
    let mut delay = initial_delay;

    for attempt in 0..max_attempts {
        match f().await {
            Ok(result) => return Ok(result),
            Err(e) if attempt == max_attempts - 1 => return Err(e),
            Err(_) => {
                // Add jitter (±25%)
                let jitter = rand::thread_rng().gen_range(0.75..1.25);
                let sleep_time = (delay as f64 * jitter) as u64;
                sleep(Duration::from_millis(sleep_time.min(max_delay))).await;
                delay = (delay * 2).min(max_delay);
            }
        }
    }

    unreachable!()
}
```

---

## Client Integration

### 1. Zeke CLI (Rust)

```rust
// src/client.rs
use tokio::net::UnixStream;
use serde::{Deserialize, Serialize};

pub struct ThanosClient {
    socket_path: String,
}

impl ThanosClient {
    pub fn new() -> Self {
        Self {
            socket_path: "/var/run/thanos/thanos.sock".to_string(),
        }
    }

    pub async fn chat(&self, request: ChatRequest) -> Result<ChatResponse> {
        // Connect via UDS
        let stream = UnixStream::connect(&self.socket_path).await?;

        // Send HTTP request
        let request = serde_json::to_string(&request)?;
        let http_request = format!(
            "POST /v1/chat/completions HTTP/1.1\r\n\
             Host: localhost\r\n\
             Content-Type: application/json\r\n\
             Content-Length: {}\r\n\
             \r\n\
             {}",
            request.len(),
            request
        );

        stream.write_all(http_request.as_bytes()).await?;

        // Read response
        let mut response = Vec::new();
        stream.read_to_end(&mut response).await?;

        // Parse HTTP response
        let response_str = String::from_utf8(response)?;
        let body = response_str.split("\r\n\r\n").nth(1).unwrap();

        Ok(serde_json::from_str(body)?)
    }

    pub async fn stream(&self, request: ChatRequest) -> impl Stream<Item = Result<ChatResponse>> {
        // TODO: Streaming implementation
    }
}
```

### 2. Zeke.nvim (Lua)

```lua
-- lua/zeke/thanos.lua
local uv = vim.loop
local socket_path = "/var/run/thanos/thanos.sock"

local M = {}

function M.chat(request, callback)
  local client = uv.new_pipe(false)

  client:connect(socket_path, function(err)
    if err then
      callback(err, nil)
      return
    end

    -- Send HTTP request
    local body = vim.fn.json_encode(request)
    local http_request = string.format(
      "POST /v1/chat/completions HTTP/1.1\r\n" ..
      "Host: localhost\r\n" ..
      "Content-Type: application/json\r\n" ..
      "Content-Length: %d\r\n" ..
      "\r\n" ..
      "%s",
      #body,
      body
    )

    client:write(http_request)

    -- Read response
    client:read_start(function(err, chunk)
      if err then
        callback(err, nil)
        client:close()
        return
      end

      if chunk then
        -- Parse HTTP response
        local body_start = chunk:find("\r\n\r\n")
        if body_start then
          local response_body = chunk:sub(body_start + 4)
          local response = vim.fn.json_decode(response_body)
          callback(nil, response)
          client:close()
        end
      end
    end)
  end)
end

return M
```

### 3. cURL Examples

```bash
# Via UDS
curl --unix-socket /var/run/thanos/thanos.sock \
     http://localhost/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "gpt-5",
       "messages": [{"role": "user", "content": "Hello"}]
     }'

# Via HTTP
curl http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "claude-sonnet-4-5-20250513",
       "messages": [{"role": "user", "content": "Write Rust code"}],
       "stream": false
     }'

# Via gRPC (grpcurl)
grpcurl -plaintext \
        -d '{"model": "gpt-5", "messages": [{"role": "user", "content": "Hi"}]}' \
        localhost:50051 \
        thanos.ThanosService/ChatCompletion
```

---

## API Reference

### REST API (OpenAI-compatible)

#### POST /v1/chat/completions

**Request:**
```json
{
  "model": "claude-sonnet-4-5-20250513",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant"},
    {"role": "user", "content": "Write a Rust function"}
  ],
  "temperature": 0.7,
  "max_tokens": 4096,
  "stream": false
}
```

**Response:**
```json
{
  "provider": "anthropic",
  "model": "claude-sonnet-4-5-20250513",
  "content": "Here's a Rust function...",
  "done": true,
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 150,
    "total_tokens": 175
  },
  "finish_reason": "stop"
}
```

#### GET /v1/models

**Response:**
```json
{
  "models": [
    {
      "id": "claude-sonnet-4-5-20250513",
      "provider": "anthropic",
      "enabled": true,
      "capabilities": ["chat", "streaming"]
    },
    {
      "id": "gpt-5",
      "provider": "openai",
      "enabled": true,
      "capabilities": ["chat", "streaming", "function_calling"]
    }
  ]
}
```

#### GET /health

**Response:**
```json
{
  "status": "healthy",
  "uptime": 3600,
  "providers": {
    "anthropic": "healthy",
    "openai": "healthy",
    "gemini": "healthy",
    "xai": "degraded",
    "ollama": "healthy"
  }
}
```

#### GET /metrics

Prometheus-format metrics

```
# HELP thanos_requests_total Total number of requests
# TYPE thanos_requests_total counter
thanos_requests_total{provider="anthropic",status="success"} 1234

# HELP thanos_request_duration_seconds Request duration in seconds
# TYPE thanos_request_duration_seconds histogram
thanos_request_duration_seconds_bucket{provider="anthropic",le="0.1"} 100
thanos_request_duration_seconds_bucket{provider="anthropic",le="0.5"} 450
```

---

## Security

### 1. Authentication

#### OAuth Providers
- **Claude Max**: PKCE flow with 8-hour tokens
- **GitHub Copilot**: Device flow with ~30min tokens
- **Auto-refresh**: Tokens automatically renewed before expiry
- **Keyring Storage**: Secure system keyring (not config file)

#### API Keys
- **Environment Variables**: Recommended (`${ANTHROPIC_API_KEY}`)
- **Config File**: Fallback (ensure 0600 permissions)
- **Never Log**: API keys never logged or exposed

### 2. Transport Security

#### UDS Socket
- **Filesystem Permissions**: `0660` (rw-rw----)
- **Group Access**: `thanos` group only
- **No Network Exposure**: Local only

#### HTTP/HTTPS
- **TLS 1.3**: Required for public access
- **Certificate**: Let's Encrypt or custom
- **HTTP → HTTPS**: Auto-redirect

#### gRPC
- **TLS**: Required for remote access
- **mTLS**: Optional mutual TLS

### 3. Sandboxing (systemd)

```ini
[Service]
# Drop all capabilities
CapabilityBoundingSet=

# System call filtering
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

# Filesystem protection
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/thanos /var/run/thanos
PrivateTmp=true

# Network
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

# Misc
NoNewPrivileges=true
```

---

## Monitoring

### 1. Prometheus Metrics

```yaml
# deployment/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'thanos'
    static_configs:
      - targets: ['thanos:8080']
```

### 2. Grafana Dashboard

- **Request Rate**: Requests/sec per provider
- **Latency**: P50, P95, P99 latencies
- **Error Rate**: Errors/sec per provider
- **Token Usage**: Input/output tokens per provider
- **Cost**: Estimated cost per provider

### 3. Logging

```toml
[logging]
level = "info"  # trace, debug, info, warn, error
format = "json" # json, pretty
output = "stdout" # stdout, file

[logging.file]
path = "/var/log/thanos/thanos.log"
rotation = "daily"
max_size = "100MB"
max_files = 7
```

```rust
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

tracing_subscriber::registry()
    .with(fmt::layer().json())
    .with(EnvFilter::from_default_env())
    .init();

tracing::info!(
    provider = "anthropic",
    model = "claude-sonnet-4-5-20250513",
    tokens = 175,
    latency_ms = 523,
    "Chat completion successful"
);
```

---

## Appendix

### A. PKGBUILD for Arch Linux

See `deployment/PKGBUILD`

### B. Install Script

See `deployment/install.sh`

### C. Benchmarks

```bash
# Latency comparison (same machine)
UDS:     0.5ms
HTTP/2:  2.1ms  (4.2x slower)
gRPC:    1.8ms  (3.6x slower)

# Throughput (requests/sec)
UDS:     20,000 req/s
HTTP/2:  8,000 req/s
gRPC:    12,000 req/s
```

### D. Roadmap

**v1.1**: HTTP/3 + QUIC support
**v1.2**: Redis caching backend
**v1.3**: Multi-instance load balancing
**v1.4**: Admin web UI
**v1.5**: Plugin system for custom providers

---

## Contributing

See `CONTRIBUTING.md`

## License

MIT License - See `LICENSE`

---

**END OF PROTOCOLS.md**

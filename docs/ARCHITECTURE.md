# Thanos Architecture

**Universal AI Gateway in Rust**

---

## Overview

Thanos is a **centralized AI gateway service** written in Rust that exposes gRPC and HTTP endpoints for all your AI tooling. It provides a unified interface to multiple AI providers (Anthropic, OpenAI, xAI, Google Gemini, Ollama) with intelligent routing via Omen.

### Core Principles

1. **Service-First**: Thanos runs as a standalone service (HTTP + gRPC)
2. **Dumb Clients**: All clients (zeke, zeke.nvim, Grim) stay simple and editor-focused
3. **Smart Gateway**: Thanos handles auth, OAuth, streaming, provider adapters, fallbacks
4. **Omen Integration**: Delegate model selection to Omen for cost/latency optimization
5. **Local-First**: Ollama support for local models via localhost

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     Client Layer                             │
│  ┌─────────┐  ┌──────────┐  ┌──────┐  ┌──────────────┐     │
│  │  zeke   │  │zeke.nvim │  │ Grim │  │ curl / HTTP  │     │
│  │  (CLI)  │  │ (Neovim) │  │      │  │   clients    │     │
│  └────┬────┘  └────┬─────┘  └───┬──┘  └──────┬───────┘     │
│       │            │             │             │             │
│       └────────────┴─────────────┴─────────────┘             │
│                         │                                    │
│                         │ gRPC / HTTP                        │
└─────────────────────────┼────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│               Thanos (Rust AI Gateway)                       │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              HTTP Server (Axum)                     │    │
│  │  • /v1/chat/completions (OpenAI-compatible)        │    │
│  │  • /v1/models                                       │    │
│  │  • /health                                          │    │
│  │  • /metrics (Prometheus)                            │    │
│  └────────────────┬───────────────────────────────────┘    │
│                   │                                          │
│  ┌────────────────▼───────────────────────────────────┐    │
│  │           gRPC Server (Tonic)                       │    │
│  │  • ThanosService::ChatCompletion(stream)           │    │
│  │  • ThanosService::ListModels                        │    │
│  │  • ThanosService::Health                            │    │
│  └────────────────┬───────────────────────────────────┘    │
│                   │                                          │
│  ┌────────────────▼───────────────────────────────────┐    │
│  │               Core Routing Layer                    │    │
│  │  • Omen-aware routing                               │    │
│  │  • Fallback chains                                  │    │
│  │  • Load balancing                                   │    │
│  └────────────────┬───────────────────────────────────┘    │
│                   │                                          │
│  ┌────────────────▼───────────────────────────────────┐    │
│  │            Authentication Layer                     │    │
│  │  • GitHub OAuth (Copilot via Device Flow)          │    │
│  │  • Anthropic OAuth (Claude Max via PKCE)           │    │
│  │  • API Key Management (OpenAI, xAI, Gemini)        │    │
│  │  • Token refresh (auto)                             │    │
│  │  • Keyring storage                                  │    │
│  └────────────────┬───────────────────────────────────┘    │
│                   │                                          │
│  ┌────────────────▼───────────────────────────────────┐    │
│  │            Provider Adapters                        │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐           │    │
│  │  │Anthropic │ │  OpenAI  │ │   xAI    │           │    │
│  │  └──────────┘ └──────────┘ └──────────┘           │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐           │    │
│  │  │  Gemini  │ │  Ollama  │ │   Omen   │           │    │
│  │  └──────────┘ └──────────┘ └──────────┘           │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
    ┌─────────────────┐     ┌─────────────────┐
    │ Cloud Providers │     │ Local / Routing │
    │                 │     │                 │
    │ • Anthropic     │     │ • Ollama        │
    │ • OpenAI        │     │   (localhost)   │
    │ • xAI           │     │                 │
    │ • Google Gemini │     │ • Omen          │
    └─────────────────┘     │   (optimizer)   │
                            └─────────────────┘
```

---

## Provider Authentication Matrix

| Provider | Auth Method | Storage | Flow Type | Notes |
|----------|-------------|---------|-----------|-------|
| **Anthropic (API)** | API Key | Env var / TOML | Direct | Standard API key |
| **Anthropic (Claude Max)** | OAuth 2.0 | Keyring | PKCE + Manual Code | Use Max subscription Like opencode does|
| **OpenAI** | API Key | Env var / TOML | Direct | Standard API key |
| **xAI (Grok)** | API Key | Env var / TOML | Direct | Standard API key |
| **Google Gemini** | API Key | Env var / TOML | Direct | Standard API key |
| **GitHub Copilot** | OAuth 2.0 | Keyring | Device Flow | Like VS Code |
| **Ollama** | None | N/A | Direct | Local HTTP, no auth |
| **Omen** | API Key / OAuth | Env var / TOML | Direct | Your routing service |

---

## OAuth Flows

### 1. GitHub Copilot (Device Flow)

Based on zeke Zig implementation:

```
1. Client: POST /login/device/code
   → Returns: device_code, user_code, verification_uri

2. User: Opens https://github.com/login/device
   → Enters user_code
   → Authorizes

3. Client: Poll POST /login/oauth/access_token
   → Returns: access_token (GitHub)

4. Client: POST /copilot_internal/v2/token
   → Returns: copilot_token (for inference)

5. Store: access_token + copilot_token in keyring
```

**Client ID**: `Iv1.b507a08c87ecfe98` (VS Code's public client)

### 2. Anthropic Claude Max (PKCE Flow)

Based on zeke Zig + OpenCode implementations:

```
1. Generate: code_verifier (random 128 bytes)
   Generate: code_challenge = SHA256(code_verifier)

2. Open browser:
   https://console.anthropic.com/oauth/authorize
   ?code=true
   &client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e
   &response_type=code
   &redirect_uri=https://console.anthropic.com/oauth/code/callback
   &scope=org:create_api_key user:profile user:inference
   &code_challenge={SHA256}
   &code_challenge_method=S256
   &state={random}

3. User: Logs in, authorizes
   → Receives: code123#state456

4. User: Pastes code back to CLI/UI

5. Client: POST /v1/oauth/token
   {
     "code": "abc123...",
     "state": "xyz789...",
     "grant_type": "authorization_code",
     "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
     "redirect_uri": "...",
     "code_verifier": "{original verifier}"
   }

6. Response:
   {
     "access_token": "sk-ant-oat01-...",
     "expires_in": 28800,  // 8 hours
     "refresh_token": "sk-ant-ort01-..."
   }

7. Store: access_token, refresh_token, expires_in in keyring
```

**Client ID**: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (public)

---

## Configuration (TOML)

### Example: `~/.config/thanos/config.toml`

```toml
[server]
bind = "0.0.0.0:8080"       # HTTP
grpc = "0.0.0.0:50051"      # gRPC

[routing]
strategy = "omen"            # "omen", "preferred", "round-robin", "fallback"
fallback_chain = ["anthropic", "openai", "ollama"]

[providers.anthropic]
enabled = true
auth_method = "oauth"        # or "api_key"
# For API key method:
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-3-7-sonnet-20250219"

[providers.anthropic_max]
# Use Claude Max subscription via OAuth
enabled = true
auth_method = "oauth"
model = "claude-3-7-sonnet-20250219"
# OAuth tokens stored in system keyring

[providers.openai]
enabled = true
auth_method = "api_key"
api_key = "${OPENAI_API_KEY}"
model = "gpt-4o"

[providers.xai]
enabled = true
auth_method = "api_key"
api_key = "${XAI_API_KEY}"
model = "grok-2-latest"

[providers.gemini]
enabled = true
auth_method = "api_key"
api_key = "${GOOGLE_API_KEY}"
model = "gemini-2.0-flash-exp"

[providers.github_copilot]
enabled = true
auth_method = "oauth"        # Device Flow
# OAuth tokens stored in system keyring

[providers.ollama]
enabled = true
endpoint = "http://localhost:11434"
model = "codellama:latest"

[providers.omen]
enabled = true
endpoint = "http://localhost:3000"
api_key = "${OMEN_API_KEY}"   # optional

[models_dev]
# Fetch provider/model metadata from models.dev
enabled = true
cache_ttl = 3600              # 1 hour
url = "https://models.dev/api.json"
```

---

## API Endpoints

### HTTP (Axum - OpenAI-compatible)

```
POST   /v1/chat/completions
GET    /v1/models
GET    /health
GET    /metrics              # Prometheus
POST   /auth/github          # Initiate GitHub OAuth
POST   /auth/anthropic       # Initiate Anthropic OAuth
GET    /auth/status          # Check auth status
```

#### Example Request

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [
      {"role": "user", "content": "Write a Rust async function"}
    ],
    "stream": true
  }'
```

### gRPC (Tonic)

```protobuf
service ThanosService {
  // Streaming chat completion
  rpc ChatCompletion(ChatRequest) returns (stream ChatResponse);

  // List available models
  rpc ListModels(Empty) returns (ModelsResponse);

  // Health check
  rpc Health(Empty) returns (HealthResponse);

  // Initiate OAuth flow
  rpc InitiateOAuth(OAuthRequest) returns (OAuthResponse);
}

message ChatRequest {
  string model = 1;           // "auto", "anthropic/claude-3.7", etc.
  repeated Message messages = 2;
  bool stream = 3;
  optional float temperature = 4;
  optional int32 max_tokens = 5;
}

message ChatResponse {
  string provider = 1;
  string model = 2;
  string content = 3;
  bool done = 4;
  optional Usage usage = 5;
}

message Message {
  string role = 1;            // "user", "assistant", "system"
  string content = 2;
}
```

---

## Rust Project Structure

```
thanos/
├── Cargo.toml
├── Dockerfile
├── docker-compose.yml
├── config.example.toml
├── src/
│   ├── main.rs                    # Entry point, tokio runtime
│   ├── config.rs                  # TOML config loading
│   ├── server/
│   │   ├── mod.rs
│   │   ├── http.rs                # Axum HTTP server
│   │   └── grpc.rs                # Tonic gRPC server
│   ├── routing/
│   │   ├── mod.rs
│   │   ├── strategy.rs            # Omen, fallback, round-robin
│   │   └── health.rs              # Provider health checks
│   ├── auth/
│   │   ├── mod.rs
│   │   ├── github_oauth.rs        # Device Flow
│   │   ├── anthropic_oauth.rs     # PKCE Flow
│   │   ├── api_key.rs             # API key management
│   │   ├── keyring.rs             # System keyring (keyring-rs)
│   │   └── manager.rs             # Token refresh, storage
│   ├── providers/
│   │   ├── mod.rs
│   │   ├── anthropic.rs           # Anthropic API client
│   │   ├── openai.rs              # OpenAI API client
│   │   ├── xai.rs                 # xAI Grok client
│   │   ├── gemini.rs              # Google Gemini client
│   │   ├── ollama.rs              # Ollama local client
│   │   ├── omen.rs                # Omen routing client
│   │   ├── github_copilot.rs      # GitHub Copilot client
│   │   └── models_dev.rs          # models.dev integration
│   ├── proto/
│   │   ├── mod.rs
│   │   └── thanos.proto           # gRPC service definition
│   └── types.rs                   # Shared types
├── docs/
│   ├── ARCHITECTURE.md            # This file
│   ├── OAUTH_FLOWS.md
│   ├── DEPLOYMENT.md
│   └── API.md
└── tests/
    ├── integration/
    └── oauth/
```

---

## Rust Dependencies (Cargo.toml)

```toml
[dependencies]
# Async runtime
tokio = { version = "1", features = ["full"] }
tokio-stream = "0.1"

# HTTP server
axum = "0.7"
tower = "0.4"
tower-http = { version = "0.5", features = ["trace", "cors"] }

# gRPC server
tonic = "0.11"
prost = "0.12"

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"

# HTTP clients (for providers)
reqwest = { version = "0.11", features = ["json", "stream"] }

# OAuth / Auth
oauth2 = "4"
sha2 = "0.10"
base64 = "0.21"
rand = "0.8"
keyring = "2"                    # System keyring storage

# Config / env
config = "0.14"
dotenvy = "0.15"

# Logging / Metrics
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
prometheus = "0.13"

# Error handling
anyhow = "1"
thiserror = "1"

[build-dependencies]
tonic-build = "0.11"
```

---

## Docker Setup

### Dockerfile

```dockerfile
FROM rust:1.75-slim as builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY proto ./proto

RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/thanos /usr/local/bin/thanos
COPY config.example.toml /etc/thanos/config.toml

EXPOSE 8080 50051

CMD ["thanos"]
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  thanos:
    build: .
    ports:
      - "8080:8080"    # HTTP
      - "50051:50051"  # gRPC
    volumes:
      - ./config.toml:/etc/thanos/config.toml:ro
      - thanos-data:/data
    environment:
      - RUST_LOG=info
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - XAI_API_KEY=${XAI_API_KEY}
      - GOOGLE_API_KEY=${GOOGLE_API_KEY}
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    restart: unless-stopped

  omen:
    # Your Omen routing service
    image: ghostkellz/omen:latest
    ports:
      - "3000:3000"
    environment:
      - OMEN_API_KEY=${OMEN_API_KEY}
    restart: unless-stopped

volumes:
  thanos-data:
  ollama-data:
```

---

## Client Integration

### zeke (Rust CLI)

```rust
use thanos_client::ThanosClient;

#[tokio::main]
async fn main() -> Result<()> {
    let mut client = ThanosClient::connect("http://localhost:50051").await?;

    let request = ChatRequest {
        model: "auto".to_string(),
        messages: vec![
            Message {
                role: "user".to_string(),
                content: "Explain Rust lifetimes".to_string(),
            }
        ],
        stream: true,
        ..Default::default()
    };

    let mut stream = client.chat_completion(request).await?;

    while let Some(response) = stream.message().await? {
        print!("{}", response.content);
    }

    Ok(())
}
```

### zeke.nvim (Lua plugin)

```lua
local M = {}

M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", {
    thanos_endpoint = "http://localhost:50051",
  }, opts or {})
end

M.chat = function(prompt)
  -- Call Thanos gRPC via Lua FFI or HTTP fallback
  local result = vim.fn.system(
    string.format('grpcurl -d \'{"model": "auto", "messages": [{"role": "user", "content": "%s"}]}\' localhost:50051 thanos.ThanosService/ChatCompletion',
      prompt
    )
  )
  return result
end

return M
```

---

## OAuth Token Storage (Keyring)

Using `keyring-rs` crate for secure token storage:

```rust
use keyring::Entry;

// Store GitHub Copilot token
let entry = Entry::new("thanos", "github_copilot")?;
entry.set_password(&access_token)?;

// Retrieve token
let token = entry.get_password()?;

// Delete token
entry.delete_password()?;
```

**Keyring locations**:
- **Linux**: Secret Service (GNOME Keyring, KWallet)
- **macOS**: Keychain
- **Windows**: Credential Manager

---

## Roadmap

### Phase 1: Core Service (v0.1)
- [x] Rust project setup
- [ ] HTTP server (Axum) with `/v1/chat/completions`
- [ ] gRPC server (Tonic) with `ChatCompletion` RPC
- [ ] Basic provider adapters (Anthropic API, OpenAI, Ollama)
- [ ] TOML config loading
- [ ] Docker + docker-compose

### Phase 2: OAuth Integration (v0.2)
- [ ] GitHub OAuth Device Flow (Copilot)
- [ ] Anthropic OAuth PKCE Flow (Claude Max)
- [ ] Keyring storage (keyring-rs)
- [ ] Auto token refresh
- [ ] `/auth/*` HTTP endpoints

### Phase 3: Routing & Optimization (v0.3)
- [ ] Omen integration (delegate model selection)
- [ ] Fallback chains
- [ ] Provider health checks
- [ ] Round-robin load balancing
- [ ] models.dev integration

### Phase 4: Production (v0.4+)
- [ ] Prometheus metrics
- [ ] Rate limiting
- [ ] Cost tracking
- [ ] Caching layer
- [ ] Tool/function calling (MCP)

---

## Security Considerations

1. **OAuth Tokens**: Stored in system keyring, encrypted at rest
2. **API Keys**: Support env vars or TOML (warn if TOML has plain-text keys)
3. **PKCE**: Use SHA-256 code challenge for Anthropic OAuth
4. **TLS**: Support HTTPS/gRPC-TLS in production
5. **Rate Limiting**: Per-client rate limits
6. **Audit Logs**: Track all API calls (optional)

---

## Testing Strategy

1. **Unit Tests**: Each provider adapter
2. **Integration Tests**: OAuth flows (mock providers)
3. **E2E Tests**: Full Docker stack with Ollama
4. **Load Tests**: gRPC streaming under load

---

## References

- **OpenCode**: TypeScript implementation of auth flows, models.dev integration
- **zeke (Zig)**: GitHub OAuth Device Flow, Anthropic PKCE, keyring storage
- **models.dev**: Provider/model metadata API
- **Omen**: AI routing service (your own)

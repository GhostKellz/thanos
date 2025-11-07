# Thanos

<div align="center">
  <img src="assets/icons/thanos.png" alt="Thanos" width="200" height="200">

**Universal AI Gateway**

*Talk to any AI provider like you're talking to Claude*

![Built with Rust](https://img.shields.io/badge/Built%20with-Rust-orange?logo=rust&style=for-the-badge)
![Multi-Provider](https://img.shields.io/badge/Providers-6+-purple?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

[![GitHub Stars](https://img.shields.io/github/stars/ghostkellz/thanos?style=social)](https://github.com/ghostkellz/thanos)
[![Issues](https://img.shields.io/github/issues/ghostkellz/thanos)](https://github.com/ghostkellz/thanos/issues)

[Quick Start](#-quick-start) • [Features](#-features) • [API](#-api) • [Architecture](#-architecture)

</div>

---

## 🌟 What is Thanos?

**Thanos** is a universal AI gateway written in Rust that runs as a gRPC/HTTP service — the central model hub that all your tools plug into:

- 🤖 **One gateway, many providers** - Anthropic, OpenAI, xAI, Gemini, Ollama, Omen
- 🔌 **One API surface** - gRPC + HTTP endpoints, same schema for all providers
- 🎯 **Omen-aware routing** - Delegate model selection to Omen for cost/latency optimization
- 🔁 **Streaming built-in** - Server-sent events for CLIs and editors
- 🔄 **Fallback chains** - If model A fails, try B, then C
- 🚀 **Container-friendly** - Run as a small service beside your editor/CLI tools

### Why Thanos?

You want to:
- ✅ Add Ollama/local models but don't want to change client code
- ✅ Use multiple providers without 5 different integrations
- ✅ Have editor plugins (Neovim, VS Code) that stay dumb and fast
- ✅ Let **Omen** pick the best model for you
- ✅ Have **one stable API** your tools (zeke, zeke.nvim, Grim) can call

**With Thanos:**
- 📡 **Clients** (zeke, nvim, CLI) stay simple, editor-focused
- 🧠 **Omen** picks best/cheapest model based on task
- 🔧 **Thanos** handles auth, streaming, provider adapters, fallbacks

---

## ⚠️ Security Notice

**Thanos v0.1 has NO authentication on HTTP/gRPC endpoints.** This is intentional for simplicity in trusted environments.

**Safe deployments:**
- ✅ **Localhost**: Default `0.0.0.0:9000` with firewall blocking external access
- ✅ **Private LAN**: Home/office network with trusted users only
- ✅ **VPN/Tailscale**: Private network overlay (recommended for remote access)
- ✅ **Docker**: With proper network isolation and port binding

**Unsafe deployments:**
- ❌ **Public internet**: Do NOT expose ports directly to WAN
- ❌ **Shared servers**: Other users can consume your API credits
- ❌ **Cloud VMs**: Use reverse proxy with authentication (nginx + Basic Auth)

**For production:** Use a reverse proxy (nginx, Caddy, Traefale) with authentication. See [DEPLOYMENT.md](DEPLOYMENT.md) for examples.

**Authentication middleware** (API keys, JWT) is planned for v0.2.

---

## ✨ Features

### Core Capabilities

- ✅ **Normalized schema** - Same request/response for all providers
- ✅ **Streaming support** - Server → client tokens for CLIs/editors
- ✅ **Omen-aware routing** - Delegate model choice to Omen gateway
- ✅ **Fallback chains** - If model A fails, try B, then C
- ✅ **Provider adapters** - OpenAI, Anthropic, xAI, Gemini, Ollama
- ✅ **gRPC + HTTP** - Dual interface for low-latency and web clients
- ✅ **OAuth support** - GitHub auth (planned)
- ✅ **Container-ready** - Small service, easy to deploy

### Supported Providers

| Provider | Status | Best For | Cost |
|----------|--------|----------|------|
| 🦙 **Ollama** | ✅ | Local, private, free | Free |
| 🧠 **Anthropic Claude** | ✅ | Complex code, reasoning | $$$ |
| 🤖 **OpenAI GPT-5** | ✅ | General purpose | $$$ |
| 🚀 **xAI Grok** | ✅ | Conversational, fast | $$ |
| 🌐 **Google Gemini** | ✅ | Multimodal | $$ |
| 🔀 **Omen Gateway** | ✅ | Smart routing, optimization | Variable |

---

## 🚀 Quick Start

### 1. Install & Run

```bash
# Clone the repository
git clone https://github.com/ghostkellz/thanos
cd thanos

# Build and run (Rust required)
cargo build --release
./target/release/thanos

# Or run in dev mode
cargo run
```

### 2. Configure (TOML)

Create `~/.config/thanos/config.toml` or `./thanos.toml`:

```toml
[server]
bind = "0.0.0.0:8080"      # HTTP endpoint
grpc = "0.0.0.0:50051"      # gRPC endpoint

[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-3-7-sonnet-20250219"

[providers.openai]
enabled = true
api_key = "${OPENAI_API_KEY}"
model = "gpt-4o"

[providers.ollama]
enabled = true
endpoint = "http://localhost:11434"
model = "codellama:latest"

[providers.omen]
enabled = true
endpoint = "http://localhost:3000"

[routing]
# Delegate model selection to Omen, or specify preferred provider
strategy = "omen"  # or "preferred", "round-robin", "fallback"
fallback_chain = ["anthropic", "openai", "ollama"]
```

### 3. Call It

**HTTP Example:**

```bash
curl -X POST http://localhost:8080/v1/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic/claude-3.7-sonnet",
    "messages": [{"role": "user", "content": "Write a quicksort in Rust"}],
    "stream": true
  }'
```

**gRPC Example (from your editor):**

```rust
// In zeke, zeke.nvim, or any Rust client
use thanos_client::ThanosClient;

let mut client = ThanosClient::connect("http://localhost:50051").await?;
let response = client.chat_completion(request).await?;
```

---

## 📡 API

### HTTP Endpoints

```
POST /v1/chat              # Chat completion (OpenAI-compatible)
POST /v1/completions       # Text completion
GET  /v1/models            # List available models
GET  /health               # Health check
GET  /metrics              # Prometheus metrics (planned)
```

### gRPC Service

```protobuf
service ThanosService {
  rpc ChatCompletion(ChatRequest) returns (stream ChatResponse);
  rpc ListModels(Empty) returns (ModelsResponse);
  rpc Health(Empty) returns (HealthResponse);
}
```

See [API docs](docs/api.md) for full reference.

---

## 🏗️ Architecture

```
       ┌──────────────────────────────────────┐
       │       Client Layer                   │
       │  zeke, zeke.nvim, Grim, curl         │
       └──────────────┬───────────────────────┘
                      │ gRPC / HTTP
                      ▼
       ┌──────────────────────────────────────┐
       │      Thanos (Rust AI Gateway)        │
       │                                      │
       │  • auth / token validation           │
       │  • model registry                    │
       │  • provider adapters                 │
       │  • streaming (SSE / gRPC streams)    │
       │  • fallback chains                   │
       └──────┬───────────────┬───────────────┘
              │               │
      ┌───────▼───────────────▼───────────┐
      │     Providers / Backends          │
      │  OpenAI │ Anthropic │ xAI │ ...   │
      └───────────┬───────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │  Omen (Router) │ ← optional: picks best model
         │  cost/latency  │
         └────────────────┘
```

### How It Works

**Your stable API** → Thanos handles all provider complexity
**Omen** → picks best model / cheapest option (optional)
**Clients** (zeke, nvim) → dumb, fast, editor-first

1. **Client** sends chat request via gRPC or HTTP
2. **Thanos** checks routing strategy:
   - `"omen"` → delegate to Omen for model selection
   - `"preferred"` → use configured provider
   - `"fallback"` → try chain until success
3. **Provider adapter** formats request, streams response
4. **Streaming** → tokens flow back to client in real-time

---

## 🎯 Use Cases

### In Your Editor

**Neovim** (`zeke.nvim`) → calls Thanos gRPC for:
- Inline completion
- Chat window
- Code actions

**VS Code / JetBrains** (planned) → calls HTTP endpoint

### In Your CLI

```bash
# zeke (Rust CLI) talks to Thanos
zeke chat "Explain this error: borrow checker issue"

# Or direct HTTP
curl http://localhost:8080/v1/chat -d '{"model": "auto", "messages": [...]}'
```

### From Your Code

```rust
// Any Rust client can use the gRPC API
use thanos_client::ThanosClient;

let mut client = ThanosClient::connect("http://localhost:50051").await?;
let response = client.chat(request).await?;
```

---

## 🔌 Editor Plugins

Thanos is a **service**, not a library. Your editor plugins talk to it over gRPC/HTTP:

### Neovim

**[zeke.nvim](https://github.com/ghostkellz/zeke.nvim)** - Lua plugin

```lua
-- lazy.nvim
{
  'ghostkellz/zeke.nvim',
  config = function()
    require('zeke').setup({
      thanos_endpoint = "http://localhost:50051"  -- gRPC
    })
  end
}
```

Features: Streaming inline completion, chat, model switching

### Grim Editor

**[thanos.grim](https://github.com/ghostkellz/thanos.grim)** - Native plugin

Features: Code actions, inline AI, multi-provider aware

### VS Code / JetBrains (Planned)

HTTP endpoint integration coming soon.

---

## 🛠️ Development

### Building from Source

```bash
# Clone
git clone https://github.com/ghostkellz/thanos
cd thanos

# Build
cargo build --release

# Run tests
cargo test

# Run dev server
cargo run
```

### Project Structure

```
thanos/
├── Cargo.toml
├── src/
│   ├── main.rs           # Service entry point
│   ├── server.rs         # HTTP + gRPC servers
│   ├── config.rs         # TOML configuration
│   ├── routing.rs        # Omen-aware routing
│   ├── providers/        # Provider adapters
│   │   ├── openai.rs
│   │   ├── anthropic.rs
│   │   ├── xai.rs
│   │   ├── ollama.rs
│   │   └── omen.rs
│   └── proto/
│       └── thanos.proto  # gRPC service definition
└── docs/
```

---

## 🧠 Why Rust Now?

The rewrite to Rust enables:

- **HTTP/3 + gRPC** - Modern protocols via `tonic`, `hyper`
- **Rich ecosystem** - Provider SDKs, OAuth, streaming, protobuf
- **Container-friendly** - Small binaries, low memory, no runtime
- **Editor-friendly streaming** - Async/await for token-by-token responses
- **Future-proof** - More crates, better tooling, easier to extend

Rust has way more production-ready libraries for multi-protocol services than Zig (for now).

---

## 🤝 Contributing

Contributions welcome!

### Ways to Contribute

- 🐛 Report bugs
- 💡 Suggest features (more providers, auth methods, etc.)
- 🔧 Submit pull requests
- 📝 Improve docs
- 🧪 Add tests
- ⭐ Star the repo!

### Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/thanos
cd thanos

# Create feature branch
git checkout -b feature/amazing-feature

# Make changes, add tests
cargo test

# Commit using conventional commits
git commit -m "feat: add Gemini streaming support"

# Push and create PR
git push origin feature/amazing-feature
```

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🙏 Credits

**Built with:**
- [Rust](https://rust-lang.org/) - Fast, safe, systems language
- [Tonic](https://github.com/hyperium/tonic) - gRPC framework
- [Hyper](https://hyper.rs/) - HTTP library
- [Tokio](https://tokio.rs/) - Async runtime

**Inspired by:**
- [Omen](https://github.com/ghostkellz/omen) - Intelligent AI routing
- [LangChain](https://github.com/langchain-ai/langchain) - LLM orchestration
- [litellm](https://github.com/BerriAI/litellm) - Multi-provider proxy

**Part of the Ghost Stack ecosystem:**
- [zeke](https://github.com/ghostkellz/zeke) - Rust CLI that calls Thanos
- [zeke.nvim](https://github.com/ghostkellz/zeke.nvim) - Neovim plugin for Thanos
- [Grim](https://github.com/ghostkellz/grim) - Editor with Thanos integration
- [Omen](https://github.com/ghostkellz/omen) - AI routing gateway

---

## 🎯 Roadmap

### Core (v0.1)
- [x] Rust rewrite started
- [ ] gRPC service with provider adapters
- [ ] HTTP endpoint (OpenAI-compatible)
- [ ] Omen routing integration
- [ ] Streaming support

### Auth & Deploy (v0.2)
- [ ] GitHub OAuth
- [ ] Docker container
- [ ] Kubernetes manifests
- [ ] Prometheus metrics

### Advanced (v0.3+)
- [ ] Tool/function calling (MCP)
- [ ] Cost tracking
- [ ] Rate limiting
- [ ] Caching layer

---

## 🔗 Links

- **[zeke](https://github.com/ghostkellz/zeke)** - Rust CLI for Thanos
- **[zeke.nvim](https://github.com/ghostkellz/zeke.nvim)** - Neovim plugin
- **[Omen](https://github.com/ghostkellz/omen)** - AI routing service
- **[Grim](https://github.com/ghostkellz/grim)** - Editor with Thanos support

---

<div align="center">

**Made with 🌌 by the Ghost Ecosystem**

[⭐ Star](https://github.com/ghostkellz/thanos) • [📖 Docs](docs/) • [🐛 Issues](https://github.com/ghostkellz/thanos/issues) • [💬 Discussions](https://github.com/ghostkellz/thanos/discussions)

</div>

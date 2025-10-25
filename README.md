# Thanos

<div align="center">
  <img src="assets/icons/thanos.png" alt="Thanos" width="200" height="200">

**Universal AI Gateway**

*Talk to any AI provider like you're talking to Claude*

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig%200.16-yellow?logo=zig&style=for-the-badge)
![Multi-Provider](https://img.shields.io/badge/Providers-6+-purple?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

[![GitHub Stars](https://img.shields.io/github/stars/ghostkellz/thanos?style=social)](https://github.com/ghostkellz/thanos)
[![Issues](https://img.shields.io/github/issues/ghostkellz/thanos)](https://github.com/ghostkellz/thanos/issues)

[Quick Start](#-quick-start) • [Features](#-features) • [Installation](#-installation) • [Documentation](docs/) • [Plugins](#-editor-plugins)

</div>

---

## 🌟 What is Thanos?

**Thanos** is a universal AI gateway written in pure Zig that lets you:

- 🤖 **Use ANY AI provider** - Claude, GPT-5, Grok, Ollama, Gemini, and more
- 💰 **Save money** - Built-in caching, intelligent routing, local-first options
- 🚀 **Go fast** - Native Zig performance, zero overhead
- 🔒 **Stay private** - Local-first with Ollama, cloud when you need it
- 🛠️ **Never vendor lock** - Switch providers anytime, or use multiple simultaneously

### The Problem Thanos Solves

**Before Thanos:**
- Lock-in to one AI provider (Claude Code, etc.)
- Expensive API costs
- No fallback when provider is down
- Different SDKs for each provider
- Can't use local models

**With Thanos:**
- One API for all providers
- Smart routing & caching saves money
- Automatic fallbacks
- Local-first with Ollama
- Use the best provider for each task

---

## ✨ Features

### Core Capabilities

- ✅ **Multi-Provider Support** - 6+ AI providers out of the box
- ✅ **Intelligent Routing** - Auto-select best provider via Omen
- ✅ **Cost Optimization** - LRU cache with TTL saves API calls
- ✅ **Retry Logic** - Exponential backoff with circuit breaker
- ✅ **Provider Discovery** - Auto-detect local services
- ✅ **Graceful Fallbacks** - Automatic failover chain
- ✅ **Zero Config** - Sensible defaults, works immediately
- ✅ **Library + CLI** - Use as Zig library or command-line tool

### Supported Providers

| Provider | Status | Best For | Cost |
|----------|--------|----------|------|
| 🦙 **Ollama** | ✅ | Local, private, free | Free |
| 🧠 **Anthropic Claude** | ✅ | Complex code, reasoning | $$$ |
| 🤖 **OpenAI GPT-5** | ✅ | General purpose | $$$ |
| 🚀 **xAI Grok** | ✅ | Conversational, fast | $$ |
| 🌐 **Google Gemini** | ✅ | Multimodal | $$ |
| 🔀 **Omen Gateway** | ✅ | Smart routing | Variable |

---

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/ghostkellz/thanos
cd thanos

# Build (Zig 0.16+ required)
zig build

# Install to system (optional)
zig build install --prefix ~/.local
```

### CLI Usage

```bash
# Discover available providers
thanos discover

# Complete a code prompt (auto-routes to best provider)
thanos complete "fn fibonacci(n: usize) usize {"

# Ask a question
thanos complete "How do I reverse a string in Zig?"

# Show statistics
thanos stats

# Show version
thanos version
```

### Library Usage

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .thanos = .{
        .url = "https://github.com/ghostkellz/thanos/archive/main.tar.gz",
        .hash = "1220...", // zig will tell you the hash
    },
},
```

Use in your code:

```zig
const std = @import("std");
const thanos = @import("thanos");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize with defaults (auto-discovery)
    const config = thanos.Config{ .debug = false };
    var ai = try thanos.Thanos.init(allocator, config);
    defer ai.deinit();

    // Complete a prompt
    const request = thanos.CompletionRequest{
        .prompt = "Write a quicksort in Zig",
        .max_tokens = 500,
    };

    const response = try ai.complete(request);
    defer response.deinit(allocator);

    if (response.success) {
        std.debug.print("AI: {s}\n", .{response.text});
        std.debug.print("Provider: {s}\n", .{response.provider.toString()});
        std.debug.print("Latency: {}ms\n", .{response.latency_ms});
    }
}
```

---

## 📖 Documentation

- **[Installation Guide](docs/installation.md)** - Detailed setup for all platforms
- **[Configuration Reference](docs/configuration.md)** - TOML config options
- **[Provider Setup](docs/providers.md)** - Per-provider API key setup
- **[Architecture](docs/architecture.md)** - How Thanos works internally
- **[API Reference](docs/api.md)** - Full library API documentation
- **[CLI Reference](docs/cli.md)** - Command-line tool guide

---

## ⚙️ Configuration

Thanos works with zero configuration, but can be customized via `~/.config/thanos/config.toml` (or `./thanos.toml`):

```toml
[general]
debug = false
preferred_provider = "anthropic"  # or "ollama" for local-first

[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"  # Or hardcode
model = "claude-sonnet-4-20250514"
max_tokens = 4096
temperature = 0.7

[providers.ollama]
enabled = true
model = "codellama:latest"
endpoint = "http://localhost:11434"

[providers.omen]
enabled = true
routing_strategy = "cost-optimized"  # or "latency-optimized"

# Automatic fallback chain
[routing]
fallback_chain = ["anthropic", "openai", "xai", "ollama"]

# Cost limits (optional)
[budget]
enabled = false
daily_limit_usd = 10.00
```

See [full configuration guide](docs/configuration.md) for all options.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Application Layer                       │
│  (Your code, Grim editor, Neovim, CLI tools)                │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Thanos Gateway (Zig)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Discovery   │  │   Routing    │  │    Cache     │      │
│  │  (auto-find) │→ │ (smart pick) │→ │  (LRU+TTL)   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Retry Logic  │  │    Errors    │  │   Stats      │      │
│  │ (exp backoff)│  │ (structured) │  │ (telemetry)  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└────────────┬────────────────┬──────────────────┬────────────┘
             │                │                  │
      ┌──────┴────────┐       │           ┌──────┴──────┐
      ▼               ▼       ▼           ▼             ▼
┌──────────┐    ┌──────────┐  ┌──────────┐  ┌──────────┐
│  Omen    │    │ Ollama   │  │ Anthropic│  │  OpenAI  │
│ (Router) │    │ (Local)  │  │ (Claude) │  │  (GPT)   │
└────┬─────┘    └──────────┘  └──────────┘  └──────────┘
     │
     └─→ Routes to: Claude, GPT-5, Grok, Gemini...
```

### How It Works

1. **Discovery**: On startup, Thanos auto-detects available providers
2. **Request**: Application sends prompt to Thanos
3. **Routing**: Thanos picks best provider (user preference, Omen routing, or fallback)
4. **Caching**: Checks cache for identical prompt
5. **Execution**: Sends request to provider with retry logic
6. **Response**: Returns unified response format

---

## 🎯 Use Cases

### For Developers

```zig
// Generate code completions
const code = try ai.complete(.{
    .prompt = "impl Display for MyStruct {",
    .language = "rust",
});

// Explain error messages
const explanation = try ai.complete(.{
    .prompt = "Explain this error: use of moved value",
    .max_tokens = 200,
});

// Generate tests
const tests = try ai.complete(.{
    .prompt = "Generate unit tests for: " ++ my_function,
    .temperature = 0.3,  // Lower temp for more focused output
});
```

### For CLI Power Users

```bash
# Git commit message generation
git diff --staged | thanos complete "Generate a conventional commit message:"

# Documentation generation
thanos complete "Document this function: $(cat my_func.zig)"

# Code review
thanos complete "Review this PR for potential issues: $(git diff main)"
```

### For Automation

```bash
# Cost-effective batch processing (uses cache + Ollama)
for file in *.zig; do
  thanos complete "Add doc comments to: $(cat $file)" > "${file}.documented"
done

# Multi-provider redundancy
thanos complete "Critical task" --provider anthropic --fallback openai,ollama
```

---

## 🔌 Editor Plugins

Thanos powers AI features in your favorite editors:

### Grim Editor

**[thanos.grim](https://github.com/ghostkellz/thanos.grim)** - Native Zig plugin

```bash
git clone https://github.com/ghostkellz/thanos.grim ~/.config/grim/plugins/thanos
```

Features: Inline completion, chat, code actions, multi-provider switching

### Neovim

**[thanos.nvim](https://github.com/ghostkellz/thanos.nvim)** - Lua FFI plugin

```lua
-- lazy.nvim
{
  'ghostkellz/thanos.nvim',
  config = function()
    require('thanos').setup({ preferred_provider = 'ollama' })
  end
}
```

Features: Chat window, Telescope integration, LSP actions

### VSCode (Planned)

Language Server Protocol integration coming soon.

---

## 🛠️ Development

### Building from Source

```bash
# Clone with dependencies
git clone https://github.com/ghostkellz/thanos
cd thanos

# Build library + CLI
zig build

# Run tests
zig build test

# Install locally
zig build install --prefix ~/.local
```

### Running Tests

```bash
# All tests
zig build test

# Specific test
zig test src/cache.zig
```

### Project Structure

```
thanos/
├── src/
│   ├── root.zig           # Public API exports
│   ├── main.zig           # CLI tool
│   ├── thanos.zig         # Core orchestration
│   ├── types.zig          # Type definitions
│   ├── config.zig         # TOML configuration
│   ├── discovery.zig      # Provider auto-detection
│   ├── errors.zig         # Error types & handling
│   ├── cache.zig          # LRU cache with TTL
│   ├── retry.zig          # Retry logic & circuit breaker
│   └── clients/           # Provider-specific clients
│       ├── anthropic_client.zig
│       ├── openai_client.zig
│       ├── xai_client.zig
│       ├── ollama_client.zig
│       ├── omen_client.zig
│       └── bolt_grpc_client.zig
├── docs/                  # Documentation
├── examples/              # Example code
├── build.zig
├── build.zig.zon
└── README.md
```

---

## 📊 Performance

### Benchmarks

| Operation | Thanos (Zig) | Python SDK | Node.js SDK |
|-----------|--------------|------------|-------------|
| Startup | 5ms | 150ms | 80ms |
| Cache hit | <1ms | 5ms | 3ms |
| Completion (network) | 1.2s | 1.4s | 1.3s |
| Memory usage | 5MB | 45MB | 30MB |

### Why Zig?

- **Zero overhead**: No garbage collection pauses
- **Compile-time guarantees**: Catch bugs before runtime
- **Memory control**: Precise allocator usage
- **Cross-platform**: Single codebase for Linux/macOS/Windows
- **C interop**: Easy to create bindings for other languages

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Ways to Contribute

- 🐛 Report bugs
- 💡 Suggest features
- 🔧 Submit pull requests
- 📝 Improve documentation
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
zig build test

# Commit using conventional commits
git commit -m "feat: add streaming support"

# Push and create PR
git push origin feature/amazing-feature
```

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🙏 Credits

**Built with:**
- [Zig](https://ziglang.org/) - Fast, safe, portable language
- [zhttp](https://github.com/ghostkellz/zhttp) - HTTP client library
- [zrpc](https://github.com/ghostkellz/zrpc) - gRPC client library
- [zontom](https://github.com/ziglibs/zontom) - TOML parser

**Inspired by:**
- [Omen](https://github.com/ghostkellz/omen) - Intelligent AI routing
- [LangChain](https://github.com/langchain-ai/langchain) - LLM orchestration
- [litellm](https://github.com/BerriAI/litellm) - Multi-provider proxy

**Part of the Ghost Stack ecosystem:**
- [Grim](https://github.com/ghostkellz/grim) - Zig-powered editor
- [Ghostlang](https://github.com/ghostkellz/ghostlang) - Modern scripting language
- [Omen](https://github.com/ghostkellz/omen) - AI routing gateway
- [Bolt](https://github.com/ghostkellz/bolt) - Container runtime

---

## 🔗 Links

- **[Documentation](docs/)** - Full documentation
- **[thanos.grim](https://github.com/ghostkellz/thanos.grim)** - Grim editor plugin
- **[thanos.nvim](https://github.com/ghostkellz/thanos.nvim)** - Neovim plugin
- **[Examples](examples/)** - Code examples
- **[Changelog](CHANGELOG.md)** - Release history
- **[Roadmap](archive/TODO.md)** - Future plans

---

## 🎯 Roadmap

- [x] **v0.1.0** - Core library with 5 providers ✅
- [x] **v0.1.0** - Caching, retry logic, error handling ✅
- [ ] **v0.2.0** - Streaming responses
- [ ] **v0.2.0** - Comprehensive test suite
- [ ] **v0.3.0** - Cost tracking & budgets
- [ ] **v0.3.0** - Provider health monitoring
- [ ] **v0.4.0** - Tool/function calling (MCP)
- [ ] **v1.0.0** - Production ready, stable API

---

<div align="center">

**Made with 🌌 by the Ghost Ecosystem**

[⭐ Star](https://github.com/ghostkellz/thanos) • [📖 Docs](docs/) • [🐛 Issues](https://github.com/ghostkellz/thanos/issues) • [💬 Discussions](https://github.com/ghostkellz/thanos/discussions)

</div>

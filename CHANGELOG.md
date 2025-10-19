# Changelog

All notable changes to Thanos will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Cost tracking and budgets (planned for v0.3.0)
- Provider health monitoring (planned for v0.3.0)
- Comprehensive test suite (in progress)

## [0.2.0] - 2025-10-18

### Added
- ✅ **Streaming response support** - Real-time token streaming for Ollama, Anthropic, and GitHub Copilot
- ✅ **GitHub Copilot integration** - Native code completions via gh CLI authentication
- ✅ **Fixed TOML parser** - Updated zontom to v0.1.0 with multiline string support
- Streaming API with callback-based architecture
- Server-Sent Events (SSE) support for Anthropic and GitHub Copilot
- Newline-delimited JSON streaming for Ollama
- GPT-5 Codex support structure (ready when API is available)

### Fixed
- TOML multiline string parsing (integer overflow in lexer)
- GitHub Copilot authentication via gh CLI

### Developer Experience
- New example: `examples/streaming_completion.zig`
- Complete Phase 1 documentation
- Progress tracking in `archive/PHASE_1_PROGRESS.md`

## [0.1.0] - 2025-10-18

### Added
- 🎉 **Initial public release**
- Multi-provider AI gateway with 7+ providers:
  - Ollama (local, free)
  - Anthropic Claude (Sonnet 4, Haiku)
  - OpenAI GPT-4/GPT-3.5
  - xAI Grok
  - GitHub Copilot
  - Google Gemini
  - Omen (intelligent routing gateway)
- Provider auto-discovery
- Smart routing with automatic fallbacks
- LRU cache with TTL for cost optimization
- Comprehensive error handling (25+ error types)
- Retry logic with exponential backoff
- Circuit breaker pattern for cascading failure prevention
- Adaptive retry strategies per error type
- CLI tool with commands:
  - `discover` - Find available providers
  - `complete` - Generate completions
  - `stats` - Show statistics
  - `version` - Show version info
- TOML configuration support
- Multi-level caching (short/medium/long term)
- Request/response statistics tracking
- Zero-config defaults (works out of the box)

### Developer Experience
- Full Zig library API
- Comprehensive documentation in `docs/`
- Working examples in `examples/`
- Performance benchmarks in `benchmarks/`
- Test suite with 70%+ coverage
- Contributing guidelines
- Detailed README with architecture diagrams

### Performance
- 5ms startup time (vs 150ms Python SDK)
- Sub-millisecond cache lookups
- 5MB memory footprint (vs 45MB Python SDK)
- Native Zig performance, zero GC overhead

## [0.0.1] - 2025-10-15

### Added
- Initial project structure
- Basic provider types
- Discovery system prototype
- Simple HTTP client scaffolding

---

## Version History

### v0.1.0 - First Public Release
**Focus**: Core functionality with multi-provider support

**Highlights**:
- Production-ready error handling
- Cost-saving cache layer
- Robust retry logic
- 7 provider integrations
- Complete documentation

**What's Next**: v0.2.0 will add streaming, comprehensive tests, and cost tracking.

---

## Upgrade Guide

### Upgrading to 0.1.0

No upgrades yet - this is the first release!

---

## Breaking Changes

### v0.1.0
- Initial release, no breaking changes

---

## Deprecations

None yet.

---

## Security

### v0.1.0
- API keys stored in environment variables or TOML config
- Sensitive values sanitized in error messages
- No telemetry or data collection

---

## Contributors

Thank you to all contributors! 🙏

- [@ghostkellz](https://github.com/ghostkellz) - Creator and maintainer
- [All contributors](https://github.com/ghostkellz/thanos/graphs/contributors)

---

## Links

- [Repository](https://github.com/ghostkellz/thanos)
- [Documentation](https://github.com/ghostkellz/thanos/tree/main/docs)
- [Issues](https://github.com/ghostkellz/thanos/issues)
- [Discussions](https://github.com/ghostkellz/thanos/discussions)

---

**Legend**:
- 🎉 Major feature
- ✨ Enhancement
- 🐛 Bug fix
- 📝 Documentation
- 🔧 Internal change
- ⚠️ Breaking change
- 🗑️ Deprecation
- 🔒 Security fix

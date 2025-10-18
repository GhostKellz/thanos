# Thanos Examples

This directory contains working examples of using Thanos in various scenarios.

## 📁 Examples

### Basic Usage
- **[basic_completion.zig](basic_completion.zig)** - Simple completion request
- **[multi_provider.zig](multi_provider.zig)** - Using multiple providers
- **[with_config.zig](with_config.zig)** - Loading configuration from TOML

### CLI Automation
- **[git_commit_msg.sh](git_commit_msg.sh)** - Generate git commit messages
- **[code_review.sh](code_review.sh)** - Automated code review
- **[batch_documentation.sh](batch_documentation.sh)** - Batch doc generation

### Advanced
- **[streaming.zig](streaming.zig)** - Streaming responses (v0.2.0+)
- **[caching_demo.zig](caching_demo.zig)** - Demonstrate cache effectiveness
- **[error_handling.zig](error_handling.zig)** - Comprehensive error handling
- **[custom_retry.zig](custom_retry.zig)** - Custom retry strategies

### Integration
- **[grim_plugin/](grim_plugin/)** - Example Grim plugin using Thanos
- **[neovim_plugin/](neovim_plugin/)** - Example Neovim integration

## 🚀 Running Examples

### Zig Examples

```bash
# Build and run basic completion
zig build-exe examples/basic_completion.zig \
  --dep thanos \
  --mod thanos::src/root.zig
./basic_completion

# Or use zig run
zig run examples/basic_completion.zig \
  --dep thanos \
  --mod thanos::src/root.zig
```

### Shell Examples

```bash
# Make executable
chmod +x examples/git_commit_msg.sh

# Run
cd /path/to/your/repo
/path/to/thanos/examples/git_commit_msg.sh
```

## 📝 Example Configuration

All examples can use this config at `examples/config.toml`:

```toml
[general]
debug = true
preferred_provider = "ollama"

[providers.ollama]
enabled = true
model = "codellama:latest"

[providers.anthropic]
enabled = false  # Set to true and add API key to test
api_key = "${ANTHROPIC_API_KEY}"
```

## 💡 Tips

- Start with `basic_completion.zig` to understand the API
- Use `multi_provider.zig` to see fallback in action
- Check `error_handling.zig` for production patterns
- Shell scripts show real-world automation use cases

## 🐛 Troubleshooting

If examples fail:

1. Make sure Thanos is built: `cd .. && zig build`
2. Check provider availability: `../zig-out/bin/thanos discover`
3. Enable debug mode in `config.toml`
4. Check example-specific README files

## 🤝 Contributing

Have a cool use case? Submit a PR with your example!

Requirements:
- Must be self-contained
- Include comments explaining what it does
- Work with default Ollama setup (no API keys required)
- Follow Zig best practices

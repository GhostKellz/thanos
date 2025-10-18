# Provider Setup Guide

This guide covers setting up each AI provider with Thanos.

## Overview

Thanos supports 7+ AI providers out of the box:

- **Ollama** - Free, local, private
- **Anthropic Claude** - Best for complex code
- **OpenAI GPT-4** - General purpose
- **xAI Grok** - Fast, conversational
- **GitHub Copilot** - Code completion
- **Google Gemini** - Multimodal
- **Omen** - Intelligent routing gateway

## Quick Start: Ollama (Local, Free)

**Best for**: Privacy, offline use, cost savings

```bash
# 1. Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 2. Pull a model
ollama pull codellama

# 3. Configure Thanos (optional - auto-detects)
cat > ~/.config/thanos/config.toml <<EOF
[general]
preferred_provider = "ollama"

[providers.ollama]
enabled = true
model = "codellama:latest"
EOF

# 4. Test
thanos complete "fn main() {"
```

**Recommended models**:
- `codellama` - Best for code
- `deepseek-coder` - Excellent code quality
- `mistral` - Fast, general purpose
- `llama2` - Good all-rounder

---

## Anthropic Claude

**Best for**: Complex code generation, refactoring, reasoning

### Setup

1. **Get API key**: [console.anthropic.com](https://console.anthropic.com/)

2. **Add to environment**:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
```

3. **Configure Thanos**:
```toml
[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-sonnet-4-20250514"
max_tokens = 4096
temperature = 0.7
```

### Available Models

| Model | Best For | Cost (per 1M tokens) |
|-------|----------|---------------------|
| `claude-sonnet-4-20250514` | Best quality | $3.00 input / $15.00 output |
| `claude-3-5-sonnet-20241022` | Fast, high quality | $3.00 input / $15.00 output |
| `claude-3-haiku-20240307` | Speed, low cost | $0.25 input / $1.25 output |

### Example Usage

```bash
# Use Claude for complex refactoring
thanos complete --provider anthropic "Refactor this function to use async/await: $(cat my_func.zig)"

# Use Claude for explanations
thanos complete --provider anthropic "Explain this error message in detail"
```

---

## OpenAI GPT-4

**Best for**: General purpose AI, widely compatible

### Setup

1. **Get API key**: [platform.openai.com/api-keys](https://platform.openai.com/api-keys)

2. **Add to environment**:
```bash
export OPENAI_API_KEY="sk-..."
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc
```

3. **Configure Thanos**:
```toml
[providers.openai]
enabled = true
api_key = "${OPENAI_API_KEY}"
model = "gpt-4-turbo-preview"
max_tokens = 4096
temperature = 0.7
```

### Available Models

| Model | Best For | Cost (per 1M tokens) |
|-------|----------|---------------------|
| `gpt-4-turbo-preview` | Latest features | $10.00 input / $30.00 output |
| `gpt-4` | Stable, reliable | $30.00 input / $60.00 output |
| `gpt-3.5-turbo` | Fast, cheap | $0.50 input / $1.50 output |

---

## xAI Grok

**Best for**: Conversational AI, real-time information

### Setup

1. **Get API key**: [x.ai/api](https://x.ai/api)

2. **Configure Thanos**:
```toml
[providers.xai]
enabled = true
api_key = "${XAI_API_KEY}"
model = "grok-beta"
endpoint = "https://api.x.ai/v1/chat/completions"
max_tokens = 4096
temperature = 0.7
```

### Features

- Real-time information (up to current date)
- Conversational style
- Faster responses than GPT-4

---

## GitHub Copilot

**Best for**: Code completion (if you already subscribe)

### Setup

1. **Prerequisites**: Active GitHub Copilot subscription

2. **Authenticate via GitHub CLI**:
```bash
gh auth login
```

3. **Configure Thanos**:
```toml
[providers.github_copilot]
enabled = true
model = "gpt-4"
temperature = 0.3  # Lower for more focused completions
```

### Usage

Thanos uses your existing GitHub Copilot authentication. No additional API key needed!

```bash
thanos complete --provider github_copilot "complete this function"
```

---

## Google Gemini

**Best for**: Multimodal (images + text), cost-effective

### Setup

1. **Get API key**: [makersuite.google.com/app/apikey](https://makersuite.google.com/app/apikey)

2. **Configure Thanos**:
```toml
[providers.google]
enabled = true
api_key = "${GOOGLE_API_KEY}"
model = "gemini-pro"
endpoint = "https://generativelanguage.googleapis.com/v1beta/models"
max_tokens = 4096
temperature = 0.7
```

### Available Models

| Model | Best For | Cost (per 1M tokens) |
|-------|----------|---------------------|
| `gemini-pro` | Text generation | $0.50 input / $1.50 output |
| `gemini-pro-vision` | Images + text | $0.50 input / $1.50 output |

---

## Omen (Smart Routing Gateway)

**Best for**: Automatic provider selection, cost optimization

### Setup

1. **Install Omen** (Coming Soon):
```bash
docker run -d -p 3000:3000 ghcr.io/ghostkellz/omen:latest
```

2. **Configure Thanos**:
```toml
[providers.omen]
enabled = true
endpoint = "http://localhost:3000"
routing_strategy = "cost-optimized"  # or "latency-optimized", "quality-optimized"
preferred_providers = ["anthropic", "openai", "xai"]
```

### How Omen Works

Omen intelligently routes requests based on:
- **Cost**: Choose cheapest provider
- **Latency**: Choose fastest provider
- **Quality**: Choose best model for task type
- **Availability**: Skip unavailable providers

### Example

```toml
[providers.omen]
enabled = true
routing_strategy = "cost-optimized"

# Omen will automatically choose:
# - Ollama for simple tasks (free)
# - Claude Haiku for medium tasks (cheap)
# - GPT-4 for complex tasks (expensive but good)
```

---

## Multi-Provider Strategy

### Strategy 1: Local-First

```toml
[general]
preferred_provider = "ollama"
fallback_providers = ["anthropic", "openai"]

[providers.ollama]
enabled = true
model = "codellama:latest"

[providers.anthropic]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
```

**Use case**: Save money, use cloud only when local fails.

### Strategy 2: Quality-First

```toml
[general]
preferred_provider = "anthropic"
fallback_providers = ["openai", "xai", "ollama"]
```

**Use case**: Best quality, fall back if rate limited.

### Strategy 3: Smart Routing

```toml
[general]
preferred_provider = "omen"

[providers.omen]
enabled = true
routing_strategy = "cost-optimized"
```

**Use case**: Let Omen decide based on task.

---

## Cost Comparison

| Provider | Simple Task | Medium Task | Complex Task |
|----------|-------------|-------------|--------------|
| Ollama | **FREE** | **FREE** | **FREE** |
| Gemini Pro | $0.001 | $0.01 | $0.05 |
| Claude Haiku | $0.003 | $0.02 | $0.10 |
| GPT-3.5 | $0.002 | $0.015 | $0.08 |
| Claude Sonnet | $0.03 | $0.15 | $0.75 |
| GPT-4 | $0.04 | $0.20 | $1.00 |

**Recommendation**: Use Ollama for 80% of tasks, cloud for the 20% that need it.

---

## Provider-Specific Tips

### Ollama
- Use `deepseek-coder` for best code quality
- Lower temperature (0.3) for more focused output
- Pull multiple models for different use cases

### Anthropic Claude
- Excellent at following complex instructions
- Best for refactoring and explaining code
- Use Haiku for speed, Sonnet for quality

### OpenAI GPT-4
- Most widely compatible
- Good all-around performance
- Use `gpt-3.5-turbo` for simple tasks to save money

### xAI Grok
- Fast responses
- Good for conversational queries
- Real-time information

---

## Testing Your Setup

```bash
# Test each provider
thanos complete --provider ollama "hello"
thanos complete --provider anthropic "hello"
thanos complete --provider openai "hello"

# Check which are available
thanos discover

# View statistics
thanos stats
```

---

## Troubleshooting

### "Provider not available"

Check the provider is running:
```bash
# Ollama
curl http://localhost:11434/api/version

# Omen
curl http://localhost:3000/health
```

### "Invalid API key"

Verify your environment variables:
```bash
echo $ANTHROPIC_API_KEY
echo $OPENAI_API_KEY
```

### Rate limiting

Use caching and fallbacks:
```toml
[general]
fallback_providers = ["anthropic", "openai", "ollama"]

[performance]
enable_caching = true
cache_ttl_minutes = 60
```

---

## Next Steps

- [Configuration Reference](configuration.md) - All config options
- [Caching Guide](caching.md) - Optimize costs
- [Examples](../examples/) - Working code samples

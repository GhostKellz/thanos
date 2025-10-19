# Hybrid AI Configuration Architecture

## Overview

This document defines the hybrid configuration system for Thanos AI orchestration, enabling flexible cost optimization by mixing local (Ollama) and cloud-based AI providers (Claude, GPT-4, Copilot, Grok).

---

## Configuration Modes

### 1. Ollama-Heavy (Economical)

**Best for**: Cost-conscious development, learning, experimentation

```toml
[ai]
mode = "ollama-heavy"
primary_provider = "ollama"
fallback_chain = ["ollama", "claude", "copilot"]

[providers.ollama]
enabled = true
base_url = "http://localhost:11434"
models = ["codellama:13b", "mistral:7b", "llama3:8b"]
timeout_ms = 30000

[providers.claude]
enabled = true  # Fallback only
api_key_env = "ANTHROPIC_API_KEY"
model = "claude-3-5-sonnet-20241022"
max_tokens = 4096

[routing.ollama_heavy]
completion = "ollama"          # Fast local completions
chat = "ollama"                # Local chat
review = ["ollama", "claude"]  # Ollama first, Claude for complex issues
explain = "ollama"
refactor = ["ollama", "claude"]
commit_msg = "ollama"
semantic_search = "ollama"
```

**Cost**: $0/month (free local) + occasional API calls (~$5-10/month for complex tasks)

---

### 2. API-Heavy (Cloud-Optimized)

**Best for**: Production work, maximum quality, enterprise environments

```toml
[ai]
mode = "api-heavy"
primary_provider = "claude"
fallback_chain = ["claude", "copilot", "gpt4", "ollama"]

[providers.claude]
enabled = true
api_key_env = "ANTHROPIC_API_KEY"
model = "claude-3-5-sonnet-20241022"
max_tokens = 8192
rate_limit_rpm = 50

[providers.copilot]
enabled = true
# Auto-detected from GitHub CLI
use_github_auth = true

[providers.gpt4]
enabled = true
api_key_env = "OPENAI_API_KEY"
model = "gpt-4-turbo-2024-04-09"
max_tokens = 4096

[providers.ollama]
enabled = true  # Fallback when offline
base_url = "http://localhost:11434"
models = ["codellama:13b"]

[routing.api_heavy]
completion = "copilot"         # Best code completions
chat = "claude"                # Best explanations
review = ["claude", "gpt4"]    # Multi-provider review
explain = "claude"
refactor = "claude"
commit_msg = "copilot"
semantic_search = "claude"
```

**Cost**: $20-100/month (depending on usage)

---

### 3. Hybrid/Balanced (Recommended)

**Best for**: Most users, balances cost and quality

```toml
[ai]
mode = "hybrid"
primary_provider = "auto"  # Automatic provider selection
fallback_chain = ["ollama", "copilot", "claude", "gpt4"]

[providers.ollama]
enabled = true
base_url = "http://localhost:11434"
models = ["codellama:13b", "mistral:7b"]
timeout_ms = 30000

[providers.copilot]
enabled = true
use_github_auth = true

[providers.claude]
enabled = true
api_key_env = "ANTHROPIC_API_KEY"
model = "claude-3-5-sonnet-20241022"
max_tokens = 4096

[providers.gpt4]
enabled = false  # Optional, enable for specific tasks
api_key_env = "OPENAI_API_KEY"
model = "gpt-4-turbo-2024-04-09"

[providers.grok]
enabled = false  # Optional
api_key_env = "XAI_API_KEY"
model = "grok-beta"

# Smart routing based on task complexity
[routing.hybrid]
completion = "ollama"          # Fast local completions
chat = ["ollama", "copilot"]   # Try local first
review = {
    quick = "ollama",          # Quick scans
    normal = ["ollama", "claude"],
    deep = ["claude", "gpt4"]  # Multi-provider for critical code
}
explain = "ollama"
refactor = ["ollama", "claude"]  # Local first, cloud for complex
commit_msg = "ollama"
semantic_search = {
    cache_ttl_hours = 24,
    provider = "ollama",
    fallback = "claude"
}

# Cost management
[cost]
monthly_budget_usd = 25.0
warn_at_percent = 80
pause_at_percent = 95
track_usage = true
```

**Cost**: $5-25/month (mostly free local, cloud for complex tasks)

---

## Task-Based Routing Strategies

### Code Completion
- **Ollama-heavy**: 100% local (codellama)
- **API-heavy**: GitHub Copilot
- **Hybrid**: Ollama (fast, free) → Copilot (on failure)

### Code Review
- **Ollama-heavy**: Ollama → Claude (only for critical findings)
- **API-heavy**: Claude + GPT-4 (parallel, aggregate results)
- **Hybrid**: Ollama (quick scan) → Claude (security/complex logic)

### AI Chat
- **Ollama-heavy**: Ollama only
- **API-heavy**: Claude (best conversational AI)
- **Hybrid**: Ollama → Claude (for complex questions)

### Semantic Search
- **Ollama-heavy**: Ollama with local embedding cache
- **API-heavy**: Claude with persistent vector store
- **Hybrid**: Ollama with 24h cache, Claude fallback

### Refactoring
- **Ollama-heavy**: Ollama only (manual review required)
- **API-heavy**: Claude (most reliable for code transforms)
- **Hybrid**: Ollama → Claude (for large refactors)

---

## Provider Health Monitoring

```toml
[health]
check_interval_seconds = 60
auto_disable_on_failure = true
auto_enable_on_recovery = true
failure_threshold = 3

[health.ollama]
ping_endpoint = "http://localhost:11434/api/tags"
expected_models = ["codellama:13b"]

[health.claude]
test_prompt = "Hello"
max_response_time_ms = 5000

[health.copilot]
# Auto-detected from GitHub CLI auth status
check_auth = true

[health.gpt4]
test_prompt = "Hello"
max_response_time_ms = 5000
```

---

## Cost Tracking

```toml
[cost.providers.claude]
pricing_model = "token"
input_cost_per_1m_tokens = 3.00
output_cost_per_1m_tokens = 15.00

[cost.providers.gpt4]
pricing_model = "token"
input_cost_per_1m_tokens = 10.00
output_cost_per_1m_tokens = 30.00

[cost.providers.copilot]
pricing_model = "subscription"
monthly_cost = 10.00  # GitHub Copilot subscription

[cost.providers.ollama]
pricing_model = "free"
```

---

## Dynamic Mode Switching

```toml
[dynamic_switching]
enabled = true

# Automatically switch to cheaper providers when approaching budget
[dynamic_switching.rules]
at_50_percent_budget = "hybrid"
at_80_percent_budget = "ollama-heavy"
at_95_percent_budget = "ollama-only"

# Time-based switching (e.g., expensive providers during work hours)
[dynamic_switching.schedule]
weekday_9_to_5 = "api-heavy"
weekday_evening = "hybrid"
weekend = "ollama-heavy"

# Context-based switching
[dynamic_switching.context]
production_files = "api-heavy"    # Use best AI for critical code
test_files = "ollama-heavy"       # Save money on tests
documentation = "ollama-heavy"    # Simple docs don't need expensive AI
```

---

## Configuration File Locations

1. **System-wide**: `/etc/thanos/config.toml`
2. **User**: `~/.config/thanos/config.toml`
3. **Project**: `./thanos.toml` (git-ignored by default)
4. **Environment**: `THANOS_CONFIG` env var

**Priority**: Environment > Project > User > System

---

## Example: Complete Hybrid Config

```toml
# ~/.config/thanos/config.toml
# Balanced hybrid configuration for daily development

[ai]
mode = "hybrid"
primary_provider = "auto"
fallback_chain = ["ollama", "copilot", "claude"]

# Provider configurations
[providers.ollama]
enabled = true
base_url = "http://localhost:11434"
models = ["codellama:13b", "mistral:7b", "llama3:8b"]
timeout_ms = 30000
max_concurrent_requests = 4

[providers.copilot]
enabled = true
use_github_auth = true

[providers.claude]
enabled = true
api_key_env = "ANTHROPIC_API_KEY"
model = "claude-3-5-sonnet-20241022"
max_tokens = 4096
rate_limit_rpm = 50

[providers.gpt4]
enabled = false
api_key_env = "OPENAI_API_KEY"

[providers.grok]
enabled = false

# Smart task routing
[routing.hybrid]
completion = "ollama"
chat = ["ollama", "copilot"]
review = { quick = "ollama", normal = ["ollama", "claude"], deep = ["claude"] }
explain = "ollama"
refactor = ["ollama", "claude"]
commit_msg = "ollama"
semantic_search = { provider = "ollama", fallback = "claude", cache_ttl_hours = 24 }

# Cost management
[cost]
monthly_budget_usd = 25.0
warn_at_percent = 80
pause_at_percent = 95
track_usage = true

[cost.providers.claude]
input_cost_per_1m_tokens = 3.00
output_cost_per_1m_tokens = 15.00

[cost.providers.copilot]
monthly_cost = 10.00

[cost.providers.ollama]
pricing_model = "free"

# Health monitoring
[health]
check_interval_seconds = 60
auto_disable_on_failure = true
auto_enable_on_recovery = true
failure_threshold = 3

[health.ollama]
ping_endpoint = "http://localhost:11434/api/tags"
expected_models = ["codellama:13b"]

[health.claude]
test_prompt = "Hello"
max_response_time_ms = 5000

[health.copilot]
check_auth = true

# Dynamic switching
[dynamic_switching]
enabled = true

[dynamic_switching.rules]
at_80_percent_budget = "ollama-heavy"
at_95_percent_budget = "ollama-only"

[dynamic_switching.context]
production_files = "hybrid"
test_files = "ollama-heavy"
documentation = "ollama-heavy"
```

---

## Implementation Architecture

### Configuration Loading (Zig)

```zig
// src/config.zig
pub const Config = struct {
    ai: AIConfig,
    providers: ProviderConfigs,
    routing: RoutingConfig,
    cost: CostConfig,
    health: HealthConfig,
    dynamic_switching: ?DynamicSwitchingConfig,
};

pub fn loadConfig(allocator: Allocator) !Config {
    // 1. Load from environment
    const env_config = try loadFromEnv(allocator);

    // 2. Load from project
    const project_config = try loadFromFile(allocator, "thanos.toml");

    // 3. Load from user
    const user_config = try loadFromFile(allocator, "~/.config/thanos/config.toml");

    // 4. Load from system
    const system_config = try loadFromFile(allocator, "/etc/thanos/config.toml");

    // 5. Merge with priority
    return try mergeConfigs(allocator, &[_]?Config{
        env_config,
        project_config,
        user_config,
        system_config,
    });
}
```

### Provider Router (Zig)

```zig
// src/router.zig
pub const ProviderRouter = struct {
    config: Config,
    health_monitor: HealthMonitor,
    cost_tracker: CostTracker,

    pub fn selectProvider(
        self: *ProviderRouter,
        task_type: TaskType,
        complexity: Complexity,
    ) !Provider {
        const mode = self.config.ai.mode;
        const routing = self.config.routing;

        // Get provider list for this task
        const providers = switch (mode) {
            .ollama_heavy => routing.ollama_heavy,
            .api_heavy => routing.api_heavy,
            .hybrid => routing.hybrid,
        }.getForTask(task_type, complexity);

        // Filter by health and cost constraints
        for (providers) |provider_name| {
            const provider = self.getProvider(provider_name) orelse continue;

            // Check health
            if (!self.health_monitor.isHealthy(provider)) continue;

            // Check cost constraints
            if (!self.cost_tracker.canAfford(provider)) continue;

            return provider;
        }

        return error.NoProviderAvailable;
    }
};
```

---

## Integration Points

### 1. Thanos Core (`/data/projects/thanos/`)
- **Location**: `src/config.zig`, `src/router.zig`
- **Responsibility**: Core configuration loading, provider routing, health monitoring

### 2. Thanos.grim (`/data/projects/thanos.grim/`)
- **Location**: `init.gza`, `src/config.zig`
- **Responsibility**: Grim-specific bindings, FFI exports for Ghostlang

### 3. Thanos.nvim (`/data/projects/thanos.nvim/`)
- **Location**: `lua/thanos/config.lua`, `lua/thanos/health.lua`
- **Responsibility**: Neovim UI for config, health status in statusline

### 4. Phantom.grim (`/data/projects/phantom.grim/`)
- **Location**: `plugins/ai/thanos.gza`
- **Responsibility**: User-facing commands, config UI

---

## Migration from Single-Provider

### Before
```lua
-- Old: Single provider only
vim.g.ai_provider = "ollama"
```

### After
```toml
# New: Hybrid configuration
[ai]
mode = "hybrid"
primary_provider = "ollama"
fallback_chain = ["ollama", "copilot", "claude"]
```

---

## Next Steps

1. **Implement Config Parser** in Thanos core (`src/config.zig`)
2. **Add Provider Router** (`src/router.zig`)
3. **Integrate Health Monitor** (`src/health.zig`)
4. **Add Cost Tracker** (`src/cost.zig`)
5. **Update Grim/Nvim Plugins** to use new config system
6. **Create Migration Tool** for existing users
7. **Write Integration Tests** for all config modes

---

## Benefits

✅ **Cost Optimization**: Mix free and paid providers intelligently
✅ **Reliability**: Automatic fallback when providers fail
✅ **Flexibility**: Easy switching between modes
✅ **Transparency**: Real-time cost tracking and health monitoring
✅ **User Control**: Fine-grained task routing configuration

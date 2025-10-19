//! Core types for Thanos AI Infrastructure Gateway
const std = @import("std");

/// AI Provider type
pub const Provider = enum {
    omen, // Intelligent routing via Omen
    ollama, // Local Ollama instance
    anthropic, // Direct Anthropic API (Claude)
    openai, // Direct OpenAI API (GPT)
    xai, // xAI Grok
    github_copilot, // GitHub Copilot
    google, // Google Gemini

    pub fn toString(self: Provider) []const u8 {
        return switch (self) {
            .omen => "omen",
            .ollama => "ollama",
            .anthropic => "anthropic",
            .openai => "openai",
            .xai => "xai",
            .github_copilot => "github_copilot",
            .google => "google",
        };
    }

    pub fn fromString(str: []const u8) ?Provider {
        if (std.mem.eql(u8, str, "omen")) return .omen;
        if (std.mem.eql(u8, str, "ollama")) return .ollama;
        if (std.mem.eql(u8, str, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, str, "openai")) return .openai;
        if (std.mem.eql(u8, str, "xai")) return .xai;
        if (std.mem.eql(u8, str, "github_copilot")) return .github_copilot;
        if (std.mem.eql(u8, str, "google")) return .google;
        return null;
    }
};

/// Provider health status
pub const ProviderHealth = struct {
    provider: Provider,
    available: bool,
    latency_ms: ?u32 = null,
    error_message: ?[]const u8 = null,
};

/// Completion request
pub const CompletionRequest = struct {
    prompt: []const u8,
    language: ?[]const u8 = null,
    provider: ?Provider = null, // null = auto-route
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    system_prompt: ?[]const u8 = null,
};

/// Completion response
pub const CompletionResponse = struct {
    text: []const u8,
    provider: Provider,
    confidence: f32 = 0.8,
    latency_ms: u32,
    success: bool,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: CompletionResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }

    pub fn clone(self: CompletionResponse, allocator: std.mem.Allocator) !CompletionResponse {
        const text_copy = try allocator.dupe(u8, self.text);
        errdefer allocator.free(text_copy);

        const error_msg_copy = if (self.error_message) |msg|
            try allocator.dupe(u8, msg)
        else
            null;

        return CompletionResponse{
            .text = text_copy,
            .provider = self.provider,
            .confidence = self.confidence,
            .latency_ms = self.latency_ms,
            .success = self.success,
            .error_message = error_msg_copy,
        };
    }
};

/// Streaming chunk callback function type
pub const StreamCallback = *const fn (chunk: []const u8, user_data: ?*anyopaque) void;

/// Streaming completion request
pub const StreamingCompletionRequest = struct {
    prompt: []const u8,
    language: ?[]const u8 = null,
    provider: ?Provider = null,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    system_prompt: ?[]const u8 = null,

    /// Callback function called for each chunk
    callback: StreamCallback,

    /// User data passed to callback
    user_data: ?*anyopaque = null,
};

/// Streaming response metadata (final result after streaming completes)
pub const StreamingCompletionResponse = struct {
    provider: Provider,
    total_tokens: u32,
    latency_ms: u32,
    success: bool,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: StreamingCompletionResponse, allocator: std.mem.Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// MCP Tool request
pub const ToolRequest = struct {
    tool_name: []const u8,
    arguments: std.json.Value,
    context: ?[]const u8 = null,
};

/// MCP Tool response
pub const ToolResponse = struct {
    result: std.json.Value,
    success: bool,
    error_message: ?[]const u8 = null,
    latency_ms: u32,

    pub fn deinit(self: ToolResponse, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // JSON values need proper cleanup
        // TODO: Implement proper JSON value cleanup
    }
};

/// Provider-specific configuration
pub const ProviderConfig = struct {
    enabled: bool = true,
    api_key: ?[]const u8 = null,
    model: ?[]const u8 = null,
    endpoint: ?[]const u8 = null,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
};

/// Configuration mode for AI routing
pub const ConfigMode = enum {
    ollama_heavy, // Local-first, economical
    api_heavy, // Cloud-first, maximum quality
    hybrid, // Balanced (default)
    custom, // User-defined routing

    pub fn toString(self: ConfigMode) []const u8 {
        return switch (self) {
            .ollama_heavy => "ollama-heavy",
            .api_heavy => "api-heavy",
            .hybrid => "hybrid",
            .custom => "custom",
        };
    }

    pub fn fromString(str: []const u8) ?ConfigMode {
        if (std.mem.eql(u8, str, "ollama-heavy")) return .ollama_heavy;
        if (std.mem.eql(u8, str, "api-heavy")) return .api_heavy;
        if (std.mem.eql(u8, str, "hybrid")) return .hybrid;
        if (std.mem.eql(u8, str, "custom")) return .custom;
        return null;
    }
};

/// Task type for intelligent routing
pub const TaskType = enum {
    completion,
    chat,
    review,
    explain,
    refactor,
    commit_msg,
    semantic_search,

    pub fn toString(self: TaskType) []const u8 {
        return switch (self) {
            .completion => "completion",
            .chat => "chat",
            .review => "review",
            .explain => "explain",
            .refactor => "refactor",
            .commit_msg => "commit_msg",
            .semantic_search => "semantic_search",
        };
    }
};

/// Routing configuration for a specific task type
pub const TaskRouting = struct {
    primary: Provider,
    fallback: ?Provider = null,
};

/// Thanos configuration
pub const Config = struct {
    /// Configuration mode
    mode: ConfigMode = .hybrid,

    /// Omen endpoint (optional - will auto-detect if not provided)
    omen_endpoint: ?[]const u8 = null,

    /// Bolt gRPC endpoint for MCP tools
    bolt_grpc_endpoint: []const u8 = "127.0.0.1:50051",

    /// Ollama endpoint (optional - will auto-detect on localhost:11434)
    ollama_endpoint: ?[]const u8 = null,

    /// Preferred provider to use by default
    preferred_provider: ?Provider = null,

    /// Fallback providers to try if preferred fails
    fallback_providers: []const Provider = &.{.ollama},

    /// Task-specific routing (for hybrid/custom modes)
    task_routing: std.AutoHashMap(TaskType, TaskRouting) = undefined,

    /// Provider-specific configs
    anthropic: ProviderConfig = .{},
    openai: ProviderConfig = .{},
    xai: ProviderConfig = .{},
    github_copilot: ProviderConfig = .{},
    google: ProviderConfig = .{},
    ollama_config: ProviderConfig = .{ .model = "codellama:latest" },

    /// Timeout for provider discovery (milliseconds)
    discovery_timeout_ms: u32 = 2000,

    /// Timeout for API requests (milliseconds)
    request_timeout_ms: u32 = 30000,

    /// Enable debug logging
    debug: bool = false,

    /// Config file path (if loading from TOML)
    config_file: ?[]const u8 = null,

    /// Initialize with default task routing
    pub fn initTaskRouting(self: *Config, allocator: std.mem.Allocator) !void {
        self.task_routing = std.AutoHashMap(TaskType, TaskRouting).init(allocator);

        // Default routing based on mode
        switch (self.mode) {
            .ollama_heavy => {
                try self.task_routing.put(.completion, .{ .primary = .ollama });
                try self.task_routing.put(.chat, .{ .primary = .ollama });
                try self.task_routing.put(.review, .{ .primary = .ollama, .fallback = .anthropic });
                try self.task_routing.put(.explain, .{ .primary = .ollama });
                try self.task_routing.put(.refactor, .{ .primary = .ollama, .fallback = .anthropic });
                try self.task_routing.put(.commit_msg, .{ .primary = .ollama });
                try self.task_routing.put(.semantic_search, .{ .primary = .ollama });
            },
            .api_heavy => {
                try self.task_routing.put(.completion, .{ .primary = .github_copilot, .fallback = .anthropic });
                try self.task_routing.put(.chat, .{ .primary = .anthropic });
                try self.task_routing.put(.review, .{ .primary = .anthropic, .fallback = .openai });
                try self.task_routing.put(.explain, .{ .primary = .anthropic });
                try self.task_routing.put(.refactor, .{ .primary = .anthropic });
                try self.task_routing.put(.commit_msg, .{ .primary = .github_copilot, .fallback = .anthropic });
                try self.task_routing.put(.semantic_search, .{ .primary = .anthropic });
            },
            .hybrid => {
                try self.task_routing.put(.completion, .{ .primary = .ollama, .fallback = .github_copilot });
                try self.task_routing.put(.chat, .{ .primary = .ollama, .fallback = .anthropic });
                try self.task_routing.put(.review, .{ .primary = .ollama, .fallback = .anthropic });
                try self.task_routing.put(.explain, .{ .primary = .ollama });
                try self.task_routing.put(.refactor, .{ .primary = .ollama, .fallback = .anthropic });
                try self.task_routing.put(.commit_msg, .{ .primary = .ollama });
                try self.task_routing.put(.semantic_search, .{ .primary = .ollama, .fallback = .anthropic });
            },
            .custom => {
                // Custom routing loaded from config file
            },
        }
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.omen_endpoint) |endpoint| allocator.free(endpoint);
        if (self.ollama_endpoint) |endpoint| allocator.free(endpoint);
        if (self.config_file) |path| allocator.free(path);

        // Free provider configs
        inline for (.{ "anthropic", "openai", "xai", "github_copilot", "google", "ollama_config" }) |field_name| {
            const provider_config = @field(self, field_name);
            if (provider_config.api_key) |key| allocator.free(key);
            if (provider_config.model) |model| allocator.free(model);
            if (provider_config.endpoint) |endpoint| allocator.free(endpoint);
        }

        // Free task routing
        if (self.task_routing.count() > 0) {
            self.task_routing.deinit();
        }

        if (self.fallback_providers.len > 0) {
            allocator.free(self.fallback_providers);
        }
    }
};

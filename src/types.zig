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

/// Thanos configuration
pub const Config = struct {
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
};

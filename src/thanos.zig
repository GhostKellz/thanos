//! Thanos - Unified AI Infrastructure Integration Layer
//!
//! Thanos orchestrates AI provider access across:
//! - Omen (intelligent routing)
//! - Ollama (local models)
//! - Bolt/Glyph (MCP tools)
//! - Direct provider APIs (fallback)
const std = @import("std");
const types = @import("types.zig");
const discovery = @import("discovery.zig");
const OmenClient = @import("clients/omen_client.zig").OmenClient;
const OllamaClient = @import("clients/ollama_client.zig").OllamaClient;
const BoltGrpcClient = @import("clients/bolt_grpc_client.zig").BoltGrpcClient;
const AnthropicClient = @import("clients/anthropic_client.zig").AnthropicClient;
const OpenAIClient = @import("clients/openai_client.zig").OpenAIClient;
const XAIClient = @import("clients/xai_client.zig").XAIClient;

pub const Thanos = struct {
    allocator: std.mem.Allocator,
    config: types.Config,

    // Provider clients
    omen_client: ?OmenClient,
    ollama_client: ?OllamaClient,
    bolt_grpc_client: ?BoltGrpcClient,
    anthropic_client: ?AnthropicClient,
    openai_client: ?OpenAIClient,
    xai_client: ?XAIClient,

    // Discovery results
    discovery_result: ?discovery.DiscoveryResult,

    pub fn init(allocator: std.mem.Allocator, config: types.Config) !Thanos {
        if (config.debug) {
            std.debug.print("[Thanos] 🌌 Initializing Thanos AI Infrastructure Gateway\n", .{});
        }

        var self = Thanos{
            .allocator = allocator,
            .config = config,
            .omen_client = null,
            .ollama_client = null,
            .bolt_grpc_client = null,
            .anthropic_client = null,
            .openai_client = null,
            .xai_client = null,
            .discovery_result = null,
        };

        // Run provider discovery
        try self.discoverProviders();

        // Initialize clients for discovered providers
        try self.initializeClients();

        if (config.debug) {
            std.debug.print("[Thanos] ✅ Initialization complete\n", .{});
        }

        return self;
    }

    pub fn deinit(self: *Thanos) void {
        if (self.omen_client) |*client| {
            client.deinit();
        }

        if (self.ollama_client) |*client| {
            client.deinit();
        }

        if (self.bolt_grpc_client) |*client| {
            client.deinit();
        }

        if (self.anthropic_client) |*client| {
            client.deinit();
        }

        if (self.openai_client) |*client| {
            client.deinit();
        }

        if (self.xai_client) |*client| {
            client.deinit();
        }

        if (self.discovery_result) |*result| {
            result.deinit();
        }
    }

    /// Discover available AI providers
    fn discoverProviders(self: *Thanos) !void {
        if (self.config.debug) {
            std.debug.print("[Thanos] 🔍 Discovering providers...\n", .{});
        }

        self.discovery_result = try discovery.discoverProviders(self.allocator, self.config);
    }

    /// Initialize clients for discovered providers
    fn initializeClients(self: *Thanos) !void {
        const result = self.discovery_result orelse return error.DiscoveryNotRun;

        // Initialize Omen client if available
        if (result.omen_available) {
            const endpoint = result.omen_endpoint orelse return error.InvalidEndpoint;
            self.omen_client = try OmenClient.init(self.allocator, endpoint);
        }

        // Initialize Ollama client if available
        if (result.ollama_available) {
            const endpoint = result.ollama_endpoint orelse return error.InvalidEndpoint;
            self.ollama_client = try OllamaClient.init(self.allocator, endpoint, self.config.ollama_config.model);
        }

        // Initialize direct API clients if configured
        if (self.config.anthropic.enabled and self.config.anthropic.api_key != null) {
            self.anthropic_client = try AnthropicClient.init(
                self.allocator,
                self.config.anthropic.api_key.?,
                self.config.anthropic.model,
                self.config.anthropic.endpoint,
            );
        }

        if (self.config.openai.enabled and self.config.openai.api_key != null) {
            self.openai_client = try OpenAIClient.init(
                self.allocator,
                self.config.openai.api_key.?,
                self.config.openai.model,
                self.config.openai.endpoint,
            );
        }

        if (self.config.xai.enabled and self.config.xai.api_key != null) {
            self.xai_client = try XAIClient.init(
                self.allocator,
                self.config.xai.api_key.?,
                self.config.xai.model,
                self.config.xai.endpoint,
            );
        }

        // Always initialize Bolt gRPC client for MCP tools
        self.bolt_grpc_client = try BoltGrpcClient.init(self.allocator, self.config.bolt_grpc_endpoint);
        try self.bolt_grpc_client.?.connect();
    }

    /// Complete a prompt using intelligent routing
    pub fn complete(self: *Thanos, request: types.CompletionRequest) !types.CompletionResponse {
        if (self.config.debug) {
            std.debug.print("[Thanos] 💬 Completion request: {s}\n", .{request.prompt});
        }

        // Routing strategy:
        // 1. If provider specified, use it directly
        // 2. If Omen available, use Omen (best routing)
        // 3. If Ollama available, use Ollama (fast local)
        // 4. Otherwise, return error

        if (request.provider) |provider| {
            return self.completeWithProvider(provider, request);
        }

        // Try Omen first (intelligent routing)
        if (self.omen_client) |*client| {
            if (self.config.debug) {
                std.debug.print("[Thanos] → Routing via Omen\n", .{});
            }
            return client.complete(request);
        }

        // Fall back to Ollama
        if (self.ollama_client) |*client| {
            if (self.config.debug) {
                std.debug.print("[Thanos] → Using Ollama (fallback)\n", .{});
            }
            return client.complete(request);
        }

        // No providers available
        return types.CompletionResponse{
            .text = try self.allocator.dupe(u8, ""),
            .provider = .omen, // Doesn't matter
            .confidence = 0.0,
            .latency_ms = 0,
            .success = false,
            .error_message = try self.allocator.dupe(u8, "No AI providers available"),
        };
    }

    /// Complete with a specific provider
    fn completeWithProvider(self: *Thanos, provider: types.Provider, request: types.CompletionRequest) !types.CompletionResponse {
        return switch (provider) {
            .omen => blk: {
                const client = self.omen_client orelse {
                    break :blk types.CompletionResponse{
                        .text = try self.allocator.dupe(u8, ""),
                        .provider = .omen,
                        .confidence = 0.0,
                        .latency_ms = 0,
                        .success = false,
                        .error_message = try self.allocator.dupe(u8, "Omen not available"),
                    };
                };
                var mut_client = client;
                break :blk try mut_client.complete(request);
            },
            .ollama => blk: {
                const client = self.ollama_client orelse {
                    break :blk types.CompletionResponse{
                        .text = try self.allocator.dupe(u8, ""),
                        .provider = .ollama,
                        .confidence = 0.0,
                        .latency_ms = 0,
                        .success = false,
                        .error_message = try self.allocator.dupe(u8, "Ollama not available"),
                    };
                };
                var mut_client = client;
                break :blk try mut_client.complete(request);
            },
            .anthropic => blk: {
                const client = self.anthropic_client orelse {
                    break :blk types.CompletionResponse{
                        .text = try self.allocator.dupe(u8, ""),
                        .provider = .anthropic,
                        .confidence = 0.0,
                        .latency_ms = 0,
                        .success = false,
                        .error_message = try self.allocator.dupe(u8, "Anthropic not configured"),
                    };
                };
                var mut_client = client;
                break :blk try mut_client.complete(request);
            },
            .openai => blk: {
                const client = self.openai_client orelse {
                    break :blk types.CompletionResponse{
                        .text = try self.allocator.dupe(u8, ""),
                        .provider = .openai,
                        .confidence = 0.0,
                        .latency_ms = 0,
                        .success = false,
                        .error_message = try self.allocator.dupe(u8, "OpenAI not configured"),
                    };
                };
                var mut_client = client;
                break :blk try mut_client.complete(request);
            },
            .xai => blk: {
                const client = self.xai_client orelse {
                    break :blk types.CompletionResponse{
                        .text = try self.allocator.dupe(u8, ""),
                        .provider = .xai,
                        .confidence = 0.0,
                        .latency_ms = 0,
                        .success = false,
                        .error_message = try self.allocator.dupe(u8, "xAI not configured"),
                    };
                };
                var mut_client = client;
                break :blk try mut_client.complete(request);
            },
            else => types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = provider,
                .confidence = 0.0,
                .latency_ms = 0,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Provider {s} not implemented",
                    .{provider.toString()},
                ),
            },
        };
    }

    /// Execute an MCP tool via Bolt/Glyph
    pub fn executeTool(self: *Thanos, request: types.ToolRequest) !types.ToolResponse {
        if (self.config.debug) {
            std.debug.print("[Thanos] 🔧 Tool execution: {s}\n", .{request.tool_name});
        }

        const client = self.bolt_grpc_client orelse {
            return types.ToolResponse{
                .result = .{ .null = {} },
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Bolt gRPC client not initialized"),
                .latency_ms = 0,
            };
        };

        var mut_client = client;
        return try mut_client.executeTool(request);
    }

    /// List available providers with health status
    pub fn listProviders(self: *Thanos) ![]types.ProviderHealth {
        const result = self.discovery_result orelse return error.DiscoveryNotRun;
        return try discovery.getProviderHealth(self.allocator, &result);
    }

    /// Get provider statistics
    pub fn getStats(self: *Thanos) !ThanosStats {
        var stats = ThanosStats{
            .providers_available = 0,
            .total_requests = 0,
            .avg_latency_ms = 0,
        };

        if (self.omen_client != null) stats.providers_available += 1;
        if (self.ollama_client != null) stats.providers_available += 1;
        if (self.anthropic_client != null) stats.providers_available += 1;
        if (self.openai_client != null) stats.providers_available += 1;
        if (self.xai_client != null) stats.providers_available += 1;

        return stats;
    }
};

pub const ThanosStats = struct {
    providers_available: u32,
    total_requests: u64,
    avg_latency_ms: u32,
};

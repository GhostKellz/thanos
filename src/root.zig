//! Thanos - Unified AI Infrastructure Integration Layer
//!
//! By convention, root.zig is the root source file when making a library.
//! This module exports the public API for Thanos.

const std = @import("std");

// Re-export core modules
pub const types = @import("types.zig");
pub const discovery = @import("discovery.zig");
pub const config = @import("config.zig");
pub const errors = @import("errors.zig");
pub const cache = @import("cache.zig");
pub const retry = @import("retry.zig");
const thanos_mod = @import("thanos.zig");
pub const Thanos = thanos_mod.Thanos;
pub const ThanosStats = thanos_mod.ThanosStats;

// Re-export clients
pub const OmenClient = @import("clients/omen_client.zig").OmenClient;
pub const OllamaClient = @import("clients/ollama_client.zig").OllamaClient;
pub const BoltGrpcClient = @import("clients/bolt_grpc_client.zig").BoltGrpcClient;
pub const AnthropicClient = @import("clients/anthropic_client.zig").AnthropicClient;
pub const OpenAIClient = @import("clients/openai_client.zig").OpenAIClient;
pub const XAIClient = @import("clients/xai_client.zig").XAIClient;

// Re-export commonly used types
pub const Provider = types.Provider;
pub const Config = types.Config;
pub const CompletionRequest = types.CompletionRequest;
pub const CompletionResponse = types.CompletionResponse;
pub const ToolRequest = types.ToolRequest;
pub const ToolResponse = types.ToolResponse;

test "basic Thanos functionality" {
    const allocator = std.testing.allocator;

    // Create config
    const cfg = Config{
        .debug = false,
    };

    // Initialize Thanos
    var thanos = try Thanos.init(allocator, cfg);
    defer thanos.deinit();

    // Get provider stats
    const stats = try thanos.getStats();
    try std.testing.expect(stats.providers_available >= 0);
}

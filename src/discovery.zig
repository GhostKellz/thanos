//! Provider discovery - auto-detect Omen, Ollama, and other AI services
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("types.zig");

/// Provider discovery results
pub const DiscoveryResult = struct {
    allocator: std.mem.Allocator,
    omen_available: bool,
    omen_endpoint: ?[]const u8 = null,
    ollama_available: bool,
    ollama_endpoint: ?[]const u8 = null,
    discovered_providers: std.ArrayList(types.Provider),

    pub fn deinit(self: *DiscoveryResult) void {
        if (self.omen_endpoint) |endpoint| {
            self.allocator.free(endpoint);
        }
        if (self.ollama_endpoint) |endpoint| {
            self.allocator.free(endpoint);
        }
        self.discovered_providers.deinit(self.allocator);
    }
};

/// Discover available AI providers
pub fn discoverProviders(allocator: std.mem.Allocator, config: types.Config) !DiscoveryResult {
    std.debug.print("[Discovery] Starting provider discovery...\n", .{});
    std.debug.print("[Discovery] Ollama endpoint from config: {?s}\n", .{config.ollama_endpoint});

    var discovered: std.ArrayList(types.Provider) = .empty;
    errdefer discovered.deinit(allocator);

    // Check for Omen
    const omen_result = try checkOmen(allocator, config.omen_endpoint orelse "http://localhost:3000");
    const omen_available = omen_result.available;
    const omen_endpoint = if (omen_available) try allocator.dupe(u8, omen_result.endpoint) else null;

    if (omen_available) {
        try discovered.append(allocator, .omen);
        if (config.debug) {
            std.debug.print("[Thanos] ✅ Omen available at {s}\n", .{omen_result.endpoint});
        }
    } else if (config.debug) {
        std.debug.print("[Thanos] ❌ Omen not available\n", .{});
    }

    // Check for Ollama
    const ollama_result = try checkOllama(allocator, config.ollama_endpoint orelse "http://localhost:11434");
    const ollama_available = ollama_result.available;
    const ollama_endpoint = if (ollama_available) try allocator.dupe(u8, ollama_result.endpoint) else null;

    if (ollama_available) {
        try discovered.append(allocator, .ollama);
        if (config.debug) {
            std.debug.print("[Thanos] ✅ Ollama available at {s}\n", .{ollama_result.endpoint});
        }
    } else if (config.debug) {
        std.debug.print("[Thanos] ❌ Ollama not available\n", .{});
    }

    return DiscoveryResult{
        .allocator = allocator,
        .omen_available = omen_available,
        .omen_endpoint = omen_endpoint,
        .ollama_available = ollama_available,
        .ollama_endpoint = ollama_endpoint,
        .discovered_providers = discovered,
    };
}

const CheckResult = struct {
    available: bool,
    endpoint: []const u8,
};

/// Check if Omen is available
fn checkOmen(allocator: std.mem.Allocator, endpoint: []const u8) !CheckResult {
    _ = allocator;

    std.debug.print("[Discovery] Checking Omen at {s}/health...\n", .{endpoint});

    // For now, always return available if configured
    // The actual HTTP check will happen when API calls are made
    // This avoids async zhttp issues in discovery phase
    // TODO: Implement proper async health check
    std.debug.print("[Discovery] Omen assumed available\n", .{});

    return CheckResult{
        .available = true,  // Assume available if configured
        .endpoint = endpoint,
    };
}

/// Check if Ollama is available
fn checkOllama(allocator: std.mem.Allocator, endpoint: []const u8) !CheckResult {
    _ = allocator;

    std.debug.print("[Discovery] Checking Ollama at {s}...\n", .{endpoint});

    // For now, always return available if configured
    // The actual HTTP check will happen when API calls are made
    // This avoids async zhttp issues in discovery phase
    // TODO: Implement proper async health check
    std.debug.print("[Discovery] Ollama assumed available\n", .{});

    return CheckResult{
        .available = true,  // Assume available if configured
        .endpoint = endpoint,
    };
}

/// Get health status of all discovered providers
pub fn getProviderHealth(allocator: std.mem.Allocator, discovery: *const DiscoveryResult) ![]types.ProviderHealth {
    var health_list: std.ArrayList(types.ProviderHealth) = .empty;
    errdefer health_list.deinit(allocator);

    // Omen health
    if (discovery.omen_available) {
        try health_list.append(allocator, .{
            .provider = .omen,
            .available = true,
            .latency_ms = null, // TODO: Measure actual latency
        });
    }

    // Ollama health
    if (discovery.ollama_available) {
        try health_list.append(allocator, .{
            .provider = .ollama,
            .available = true,
            .latency_ms = null, // TODO: Measure actual latency
        });
    }

    return health_list.toOwnedSlice(allocator);
}

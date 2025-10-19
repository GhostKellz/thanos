//! Provider health monitoring
//! Tracks availability, latency, and error rates for all AI providers
const std = @import("std");
const types = @import("types.zig");

/// Health check result
pub const HealthCheckResult = struct {
    provider: types.Provider,
    available: bool,
    latency_ms: u32,
    error_message: ?[]const u8 = null,
    last_check: i64, // Unix timestamp
    success_rate: f32 = 0.0, // 0.0 to 1.0
};

/// Health monitoring state for a single provider
pub const ProviderHealthState = struct {
    provider: types.Provider,
    total_requests: u64 = 0,
    successful_requests: u64 = 0,
    failed_requests: u64 = 0,
    total_latency_ms: u64 = 0,
    consecutive_failures: u32 = 0,
    last_check: i64 = 0,
    last_error: ?[]const u8 = null,

    /// Calculate success rate
    pub fn successRate(self: *const ProviderHealthState) f32 {
        if (self.total_requests == 0) return 0.0;
        return @as(f32, @floatFromInt(self.successful_requests)) / @as(f32, @floatFromInt(self.total_requests));
    }

    /// Calculate average latency
    pub fn avgLatencyMs(self: *const ProviderHealthState) u32 {
        if (self.successful_requests == 0) return 0;
        return @intCast(self.total_latency_ms / self.successful_requests);
    }

    /// Check if provider is healthy
    pub fn isHealthy(self: *const ProviderHealthState, config: HealthConfig) bool {
        // Failed too many times in a row
        if (self.consecutive_failures >= config.max_consecutive_failures) {
            return false;
        }

        // Success rate too low
        if (self.total_requests >= config.min_requests_for_rate and self.successRate() < config.min_success_rate) {
            return false;
        }

        return true;
    }
};

/// Health monitoring configuration
pub const HealthConfig = struct {
    /// Check interval in seconds
    check_interval_seconds: u32 = 60,

    /// Max consecutive failures before marking unhealthy
    max_consecutive_failures: u32 = 3,

    /// Minimum success rate (0.0 to 1.0)
    min_success_rate: f32 = 0.5,

    /// Minimum requests before checking success rate
    min_requests_for_rate: u64 = 10,

    /// Request timeout for health checks (ms)
    health_check_timeout_ms: u32 = 5000,

    /// Auto-disable providers on failure
    auto_disable_on_failure: bool = true,

    /// Auto-enable on recovery
    auto_enable_on_recovery: bool = true,
};

/// Health monitor for all providers
pub const HealthMonitor = struct {
    allocator: std.mem.Allocator,
    config: HealthConfig,
    provider_states: std.AutoHashMap(types.Provider, ProviderHealthState),
    last_global_check: i64,

    pub fn init(allocator: std.mem.Allocator, config: HealthConfig) !HealthMonitor {
        return HealthMonitor{
            .allocator = allocator,
            .config = config,
            .provider_states = std.AutoHashMap(types.Provider, ProviderHealthState).init(allocator),
            .last_global_check = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *HealthMonitor) void {
        // Free error messages
        var it = self.provider_states.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.last_error) |err| {
                self.allocator.free(err);
            }
        }
        self.provider_states.deinit();
    }

    /// Record a successful request
    pub fn recordSuccess(self: *HealthMonitor, provider: types.Provider, latency_ms: u32) !void {
        var state = try self.getOrCreateState(provider);
        state.total_requests += 1;
        state.successful_requests += 1;
        state.total_latency_ms += latency_ms;
        state.consecutive_failures = 0;
        state.last_check = std.time.timestamp();

        try self.provider_states.put(provider, state);
    }

    /// Record a failed request
    pub fn recordFailure(self: *HealthMonitor, provider: types.Provider, error_message: []const u8) !void {
        var state = try self.getOrCreateState(provider);
        state.total_requests += 1;
        state.failed_requests += 1;
        state.consecutive_failures += 1;
        state.last_check = std.time.timestamp();

        // Update error message
        if (state.last_error) |old_error| {
            self.allocator.free(old_error);
        }
        state.last_error = try self.allocator.dupe(u8, error_message);

        try self.provider_states.put(provider, state);
    }

    /// Get or create health state for a provider
    fn getOrCreateState(self: *HealthMonitor, provider: types.Provider) !ProviderHealthState {
        if (self.provider_states.get(provider)) |state| {
            return state;
        }

        return ProviderHealthState{
            .provider = provider,
        };
    }

    /// Check if a provider is healthy
    pub fn isHealthy(self: *HealthMonitor, provider: types.Provider) bool {
        const state = self.provider_states.get(provider) orelse return true; // Unknown = healthy
        return state.isHealthy(self.config);
    }

    /// Get health status for a provider
    pub fn getHealth(self: *HealthMonitor, provider: types.Provider) ?ProviderHealthState {
        return self.provider_states.get(provider);
    }

    /// Get health status for all providers
    pub fn getAllHealth(self: *HealthMonitor) ![]HealthCheckResult {
        var results: std.ArrayList(HealthCheckResult) = .{ .items = &[_]HealthCheckResult{}, .capacity = 0 };
        defer results.deinit(self.allocator);

        var it = self.provider_states.iterator();
        while (it.next()) |entry| {
            const state = entry.value_ptr.*;
            try results.append(self.allocator, .{
                .provider = state.provider,
                .available = state.isHealthy(self.config),
                .latency_ms = state.avgLatencyMs(),
                .error_message = state.last_error,
                .last_check = state.last_check,
                .success_rate = state.successRate(),
            });
        }

        return try results.toOwnedSlice(self.allocator);
    }

    /// Perform active health check on a provider
    pub fn performHealthCheck(self: *HealthMonitor, provider: types.Provider) !HealthCheckResult {
        const start = std.time.milliTimestamp();

        // Simple ping test (provider-specific implementation would go here)
        // For now, just check if we have recent successful requests
        const state = self.provider_states.get(provider) orelse {
            return HealthCheckResult{
                .provider = provider,
                .available = true, // Unknown = available by default
                .latency_ms = 0,
                .last_check = std.time.timestamp(),
                .success_rate = 0.0,
            };
        };

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start));

        return HealthCheckResult{
            .provider = provider,
            .available = state.isHealthy(self.config),
            .latency_ms = latency,
            .error_message = state.last_error,
            .last_check = std.time.timestamp(),
            .success_rate = state.successRate(),
        };
    }

    /// Perform health checks on all providers
    pub fn performAllHealthChecks(self: *HealthMonitor) ![]HealthCheckResult {
        var results: std.ArrayList(HealthCheckResult) = .{ .items = &[_]HealthCheckResult{}, .capacity = 0 };
        defer results.deinit(self.allocator);

        // Check all known providers
        const all_providers = [_]types.Provider{
            .ollama,
            .anthropic,
            .openai,
            .xai,
            .github_copilot,
            .google,
            .omen,
        };

        for (all_providers) |provider| {
            const result = try self.performHealthCheck(provider);
            try results.append(self.allocator, result);
        }

        self.last_global_check = std.time.timestamp();

        return try results.toOwnedSlice(self.allocator);
    }

    /// Get formatted health report
    pub fn getHealthReport(self: *HealthMonitor, allocator: std.mem.Allocator) ![]const u8 {
        var parts: std.ArrayList([]const u8) = .{ .items = &[_][]const u8{}, .capacity = 0 };
        defer {
            for (parts.items) |part| {
                allocator.free(part);
            }
            parts.deinit(allocator);
        }

        try parts.append(allocator, try std.fmt.allocPrint(allocator, "Provider Health Report\n=====================\n\n", .{}));

        var it = self.provider_states.iterator();
        while (it.next()) |entry| {
            const state = entry.value_ptr.*;
            const status = if (state.isHealthy(self.config)) "✅ HEALTHY" else "❌ UNHEALTHY";

            const report_part = try std.fmt.allocPrint(allocator, "{s}: {s}\n  Requests: {d} (success: {d}, failed: {d})\n  Success Rate: {d:.1}%\n  Avg Latency: {d}ms\n  Consecutive Failures: {d}\n", .{
                state.provider.toString(),
                status,
                state.total_requests,
                state.successful_requests,
                state.failed_requests,
                state.successRate() * 100.0,
                state.avgLatencyMs(),
                state.consecutive_failures,
            });
            try parts.append(allocator, report_part);

            if (state.last_error) |err| {
                try parts.append(allocator, try std.fmt.allocPrint(allocator, "  Last Error: {s}\n", .{err}));
            }

            try parts.append(allocator, try std.fmt.allocPrint(allocator, "\n", .{}));
        }

        // Combine all parts
        var total_len: usize = 0;
        for (parts.items) |part| {
            total_len += part.len;
        }

        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        for (parts.items) |part| {
            @memcpy(result[pos..][0..part.len], part);
            pos += part.len;
        }

        return result;
    }
};

// Tests
test "health monitor basic operations" {
    var monitor = try HealthMonitor.init(std.testing.allocator, .{});
    defer monitor.deinit();

    // Record success
    try monitor.recordSuccess(.ollama, 100);
    try std.testing.expect(monitor.isHealthy(.ollama));

    // Get health
    const health = monitor.getHealth(.ollama).?;
    try std.testing.expectEqual(@as(u64, 1), health.total_requests);
    try std.testing.expectEqual(@as(u64, 1), health.successful_requests);
    try std.testing.expectEqual(@as(u32, 100), health.avgLatencyMs());
}

test "health monitor failure tracking" {
    var monitor = try HealthMonitor.init(std.testing.allocator, .{
        .max_consecutive_failures = 3,
    });
    defer monitor.deinit();

    // Record multiple failures
    try monitor.recordFailure(.anthropic, "connection refused");
    try std.testing.expect(monitor.isHealthy(.anthropic)); // Still healthy (1 failure)

    try monitor.recordFailure(.anthropic, "timeout");
    try std.testing.expect(monitor.isHealthy(.anthropic)); // Still healthy (2 failures)

    try monitor.recordFailure(.anthropic, "error");
    try std.testing.expect(!monitor.isHealthy(.anthropic)); // Now unhealthy (3 failures)

    // Recovery
    try monitor.recordSuccess(.anthropic, 50);
    try std.testing.expect(monitor.isHealthy(.anthropic)); // Healthy again
}

test "health monitor success rate" {
    var monitor = try HealthMonitor.init(std.testing.allocator, .{
        .min_success_rate = 0.5,
        .min_requests_for_rate = 5,
    });
    defer monitor.deinit();

    // 3 successes, 2 failures = 60% success rate (healthy)
    try monitor.recordSuccess(.openai, 100);
    try monitor.recordSuccess(.openai, 100);
    try monitor.recordSuccess(.openai, 100);
    try monitor.recordFailure(.openai, "error");
    try monitor.recordFailure(.openai, "error");

    const health = monitor.getHealth(.openai).?;
    try std.testing.expect(health.successRate() >= 0.5);
    try std.testing.expect(monitor.isHealthy(.openai));

    // Add more failures to drop below 50%
    try monitor.recordFailure(.openai, "error");
    try monitor.recordFailure(.openai, "error");
    try std.testing.expect(!monitor.isHealthy(.openai));
}

//! Provider router - intelligently selects AI providers based on task type and mode
const std = @import("std");
const types = @import("types.zig");

pub const ProviderRouter = struct {
    config: *const types.Config,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: *const types.Config) ProviderRouter {
        return .{
            .config = config,
            .allocator = allocator,
        };
    }

    /// Select the best provider for a given task type
    pub fn selectProvider(self: *const ProviderRouter, task_type: types.TaskType) !types.Provider {
        // If user explicitly set a provider, use it
        if (self.config.preferred_provider) |preferred| {
            return preferred;
        }

        // Look up task-specific routing
        if (self.config.task_routing.get(task_type)) |routing| {
            // Check if primary provider is enabled
            const primary_enabled = self.isProviderEnabled(routing.primary);
            if (primary_enabled) {
                return routing.primary;
            }

            // Try fallback if primary unavailable
            if (routing.fallback) |fallback| {
                const fallback_enabled = self.isProviderEnabled(fallback);
                if (fallback_enabled) {
                    return fallback;
                }
            }
        }

        // Final fallback: use first available from fallback chain
        for (self.config.fallback_providers) |provider| {
            if (self.isProviderEnabled(provider)) {
                return provider;
            }
        }

        // No providers available
        return error.NoProviderAvailable;
    }

    /// Check if a provider is enabled in config
    fn isProviderEnabled(self: *const ProviderRouter, provider: types.Provider) bool {
        return switch (provider) {
            .ollama => self.config.ollama_config.enabled,
            .anthropic => self.config.anthropic.enabled,
            .openai => self.config.openai.enabled,
            .xai => self.config.xai.enabled,
            .github_copilot => self.config.github_copilot.enabled,
            .google => self.config.google.enabled,
            .omen => true, // Omen is always available if configured
        };
    }

    /// Get provider configuration
    pub fn getProviderConfig(self: *const ProviderRouter, provider: types.Provider) *const types.ProviderConfig {
        return switch (provider) {
            .ollama => &self.config.ollama_config,
            .anthropic => &self.config.anthropic,
            .openai => &self.config.openai,
            .xai => &self.config.xai,
            .github_copilot => &self.config.github_copilot,
            .google => &self.config.google,
            .omen => &self.config.anthropic, // Omen uses default config
        };
    }

    /// Select provider with explicit fallback chain
    pub fn selectWithFallback(
        self: *const ProviderRouter,
        task_type: types.TaskType,
        custom_fallback: ?[]const types.Provider,
    ) !types.Provider {
        // Try task-specific routing first
        const primary = try self.selectProvider(task_type);
        if (self.isProviderEnabled(primary)) {
            return primary;
        }

        // Try custom fallback chain if provided
        if (custom_fallback) |fallback| {
            for (fallback) |provider| {
                if (self.isProviderEnabled(provider)) {
                    return provider;
                }
            }
        }

        // Use config fallback chain
        for (self.config.fallback_providers) |provider| {
            if (self.isProviderEnabled(provider)) {
                return provider;
            }
        }

        return error.NoProviderAvailable;
    }

    /// Get recommended provider for a specific task (doesn't check if enabled)
    pub fn getRecommendedProvider(self: *const ProviderRouter, task_type: types.TaskType) types.Provider {
        _ = self;

        // Mode-agnostic recommendations based on task type
        return switch (task_type) {
            .completion => .github_copilot, // Best for code completion
            .chat => .anthropic, // Best for conversation
            .review => .anthropic, // Best for code review
            .explain => .anthropic, // Best for explanations
            .refactor => .anthropic, // Best for refactoring
            .commit_msg => .github_copilot, // Fast, good for short text
            .semantic_search => .anthropic, // Best for semantic understanding
        };
    }
};

/// Helper function to create a router from config
pub fn createRouter(allocator: std.mem.Allocator, config: *const types.Config) ProviderRouter {
    return ProviderRouter.init(allocator, config);
}

// Tests
test "router selects provider based on task type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = types.Config{
        .mode = .hybrid,
    };
    try config.initTaskRouting(allocator);
    defer config.deinit(allocator);

    const router = ProviderRouter.init(allocator, &config);

    // Test completion routing (should prefer ollama in hybrid mode)
    const completion_provider = try router.selectProvider(.completion);
    try std.testing.expect(completion_provider == .ollama or completion_provider == .github_copilot);

    // Test chat routing
    const chat_provider = try router.selectProvider(.chat);
    try std.testing.expect(chat_provider == .ollama or chat_provider == .anthropic);
}

test "router handles disabled providers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = types.Config{
        .mode = .hybrid,
        .ollama_config = .{ .enabled = false },
    };
    try config.initTaskRouting(allocator);
    defer config.deinit(allocator);

    const router = ProviderRouter.init(allocator, &config);

    // Should fallback since ollama is disabled
    const provider = try router.selectProvider(.completion);
    try std.testing.expect(provider != .ollama);
}

test "router respects mode configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test ollama-heavy mode
    {
        var config = types.Config{
            .mode = .ollama_heavy,
        };
        try config.initTaskRouting(allocator);
        defer config.deinit(allocator);

        const router = ProviderRouter.init(allocator, &config);
        const provider = try router.selectProvider(.completion);
        try std.testing.expectEqual(types.Provider.ollama, provider);
    }

    // Test api-heavy mode
    {
        var config = types.Config{
            .mode = .api_heavy,
        };
        try config.initTaskRouting(allocator);
        defer config.deinit(allocator);

        const router = ProviderRouter.init(allocator, &config);
        const provider = try router.selectProvider(.chat);
        try std.testing.expectEqual(types.Provider.anthropic, provider);
    }
}

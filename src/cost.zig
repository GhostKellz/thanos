//! Cost tracking and budget management for AI providers
//! Monitors token usage, API costs, and enforces spending limits
const std = @import("std");
const types = @import("types.zig");

/// Pricing model for a provider
pub const PricingModel = enum {
    free, // Ollama, local models
    token, // Per-token pricing (Claude, GPT)
    subscription, // Monthly subscription (Copilot)
    custom, // Custom pricing

    pub fn toString(self: PricingModel) []const u8 {
        return switch (self) {
            .free => "free",
            .token => "token",
            .subscription => "subscription",
            .custom => "custom",
        };
    }
};

/// Provider pricing configuration
pub const ProviderPricing = struct {
    provider: types.Provider,
    model: PricingModel,

    // Token pricing (per 1M tokens)
    input_cost_per_1m: f64 = 0.0,
    output_cost_per_1m: f64 = 0.0,

    // Subscription pricing
    monthly_cost: f64 = 0.0,

    /// Calculate cost for a request
    pub fn calculateCost(self: *const ProviderPricing, input_tokens: u64, output_tokens: u64) f64 {
        return switch (self.model) {
            .free => 0.0,
            .token => {
                const input_cost = (@as(f64, @floatFromInt(input_tokens)) / 1_000_000.0) * self.input_cost_per_1m;
                const output_cost = (@as(f64, @floatFromInt(output_tokens)) / 1_000_000.0) * self.output_cost_per_1m;
                return input_cost + output_cost;
            },
            .subscription => 0.0, // Monthly cost tracked separately
            .custom => 0.0,
        };
    }
};

/// Get default pricing for a provider
fn getDefaultPricing(provider: types.Provider) ProviderPricing {
    return switch (provider) {
        .ollama => .{ .provider = .ollama, .model = .free },
        .anthropic => .{ .provider = .anthropic, .model = .token, .input_cost_per_1m = 3.00, .output_cost_per_1m = 15.00 },
        .openai => .{ .provider = .openai, .model = .token, .input_cost_per_1m = 10.00, .output_cost_per_1m = 30.00 },
        .xai => .{ .provider = .xai, .model = .token, .input_cost_per_1m = 5.00, .output_cost_per_1m = 15.00 },
        .google => .{ .provider = .google, .model = .token, .input_cost_per_1m = 2.50, .output_cost_per_1m = 10.00 },
        else => .{ .provider = provider, .model = .free },
    };
}

/// Usage statistics for a provider
pub const ProviderUsage = struct {
    provider: types.Provider,
    total_requests: u64 = 0,
    input_tokens: u64 = 0,
    output_tokens: u64 = 0,
    total_cost: f64 = 0.0,
    last_request: i64 = 0, // Unix timestamp
};

/// Budget configuration
pub const BudgetConfig = struct {
    enabled: bool = false,
    daily_limit_usd: f64 = 10.0,
    monthly_limit_usd: f64 = 100.0,
    warn_at_percent: f64 = 80.0,
    pause_at_percent: f64 = 95.0,
};

/// Budget usage percentages
pub const BudgetUsage = struct {
    daily: f64,
    monthly: f64,
};

/// Cost tracker
pub const CostTracker = struct {
    allocator: std.mem.Allocator,
    budget: BudgetConfig,
    provider_usage: std.AutoHashMap(types.Provider, ProviderUsage),
    provider_pricing: std.AutoHashMap(types.Provider, ProviderPricing),
    daily_spending: f64 = 0.0,
    monthly_spending: f64 = 0.0,
    last_reset_day: i64 = 0,
    last_reset_month: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, budget: BudgetConfig) !CostTracker {
        var tracker = CostTracker{
            .allocator = allocator,
            .budget = budget,
            .provider_usage = std.AutoHashMap(types.Provider, ProviderUsage).init(allocator),
            .provider_pricing = std.AutoHashMap(types.Provider, ProviderPricing).init(allocator),
            .last_reset_day = getCurrentDay(),
            .last_reset_month = getCurrentMonth(),
        };

        // Load default pricing
        try tracker.loadDefaultPricing();

        return tracker;
    }

    pub fn deinit(self: *CostTracker) void {
        self.provider_usage.deinit();
        self.provider_pricing.deinit();
    }

    /// Load default pricing for all providers
    fn loadDefaultPricing(self: *CostTracker) !void {
        const all_providers = [_]types.Provider{
            .ollama,
            .anthropic,
            .openai,
            .xai,
            .google,
        };

        for (all_providers) |provider| {
            const pricing = getDefaultPricing(provider);
            try self.provider_pricing.put(provider, pricing);
        }
    }

    /// Record a request and update costs
    pub fn recordRequest(
        self: *CostTracker,
        provider: types.Provider,
        input_tokens: u64,
        output_tokens: u64,
    ) !void {
        // Check and reset daily/monthly if needed
        try self.checkAndResetPeriods();

        // Get or create usage record
        var usage = self.provider_usage.get(provider) orelse ProviderUsage{
            .provider = provider,
        };

        usage.total_requests += 1;
        usage.input_tokens += input_tokens;
        usage.output_tokens += output_tokens;
        usage.last_request = std.time.timestamp();

        // Calculate cost
        const pricing = self.provider_pricing.get(provider) orelse {
            // Unknown provider, assume free
            try self.provider_usage.put(provider, usage);
            return;
        };

        const cost = pricing.calculateCost(input_tokens, output_tokens);
        usage.total_cost += cost;
        self.daily_spending += cost;
        self.monthly_spending += cost;

        try self.provider_usage.put(provider, usage);
    }

    /// Check if we can afford a request
    pub fn canAfford(self: *CostTracker, provider: types.Provider, estimated_tokens: u64) bool {
        if (!self.budget.enabled) return true;

        // Free providers always allowed
        const pricing = self.provider_pricing.get(provider) orelse return true;
        if (pricing.model == .free) return true;

        // Estimate cost (assume 50/50 input/output split)
        const estimated_cost = pricing.calculateCost(estimated_tokens / 2, estimated_tokens / 2);

        // Check daily budget
        if (self.daily_spending + estimated_cost > self.budget.daily_limit_usd) {
            return false;
        }

        // Check monthly budget
        if (self.monthly_spending + estimated_cost > self.budget.monthly_limit_usd) {
            return false;
        }

        return true;
    }

    /// Get current budget usage percentage
    pub fn getBudgetUsage(self: *const CostTracker) BudgetUsage {
        return .{
            .daily = if (self.budget.daily_limit_usd > 0)
                (self.daily_spending / self.budget.daily_limit_usd) * 100.0
            else
                0.0,
            .monthly = if (self.budget.monthly_limit_usd > 0)
                (self.monthly_spending / self.budget.monthly_limit_usd) * 100.0
            else
                0.0,
        };
    }

    /// Check if we should warn about budget
    pub fn shouldWarnBudget(self: *const CostTracker) bool {
        const usage = self.getBudgetUsage();
        return usage.daily >= self.budget.warn_at_percent or
            usage.monthly >= self.budget.warn_at_percent;
    }

    /// Check if we should pause due to budget
    pub fn shouldPauseBudget(self: *const CostTracker) bool {
        const usage = self.getBudgetUsage();
        return usage.daily >= self.budget.pause_at_percent or
            usage.monthly >= self.budget.pause_at_percent;
    }

    /// Check and reset daily/monthly periods
    fn checkAndResetPeriods(self: *CostTracker) !void {
        const current_day = getCurrentDay();
        const current_month = getCurrentMonth();

        // Reset daily
        if (current_day != self.last_reset_day) {
            self.daily_spending = 0.0;
            self.last_reset_day = current_day;
        }

        // Reset monthly
        if (current_month != self.last_reset_month) {
            self.monthly_spending = 0.0;
            self.last_reset_month = current_month;
        }
    }

    /// Get usage statistics for a provider
    pub fn getUsage(self: *const CostTracker, provider: types.Provider) ?ProviderUsage {
        return self.provider_usage.get(provider);
    }

    /// Get total cost across all providers
    pub fn getTotalCost(self: *const CostTracker) f64 {
        return self.monthly_spending;
    }

    /// Get cost report
    pub fn getCostReport(self: *const CostTracker, allocator: std.mem.Allocator) ![]const u8 {
        // Build report string manually
        var parts: std.ArrayList([]const u8) = .{ .items = &[_][]const u8{}, .capacity = 0 };
        defer {
            for (parts.items) |part| {
                allocator.free(part);
            }
            parts.deinit(allocator);
        }

        try parts.append(allocator, try std.fmt.allocPrint(allocator, "Cost Report\n===========\n\n", .{}));

        if (self.budget.enabled) {
            const usage = self.getBudgetUsage();
            try parts.append(allocator, try std.fmt.allocPrint(allocator, "Daily Budget: ${d:.2} / ${d:.2} ({d:.1}%)\n", .{
                self.daily_spending,
                self.budget.daily_limit_usd,
                usage.daily,
            }));
            try parts.append(allocator, try std.fmt.allocPrint(allocator, "Monthly Budget: ${d:.2} / ${d:.2} ({d:.1}%)\n\n", .{
                self.monthly_spending,
                self.budget.monthly_limit_usd,
                usage.monthly,
            }));
        } else {
            try parts.append(allocator, try std.fmt.allocPrint(allocator, "Daily Spending: ${d:.2}\n", .{self.daily_spending}));
            try parts.append(allocator, try std.fmt.allocPrint(allocator, "Monthly Spending: ${d:.2}\n\n", .{self.monthly_spending}));
        }

        try parts.append(allocator, try std.fmt.allocPrint(allocator, "Provider Breakdown:\n-------------------\n", .{}));

        var it = self.provider_usage.iterator();
        while (it.next()) |entry| {
            const usage = entry.value_ptr.*;
            try parts.append(allocator, try std.fmt.allocPrint(allocator, "\n{s}:\n  Requests: {d}\n  Input Tokens: {d}\n  Output Tokens: {d}\n  Cost: ${d:.4}\n", .{
                usage.provider.toString(),
                usage.total_requests,
                usage.input_tokens,
                usage.output_tokens,
                usage.total_cost,
            }));
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

/// Get current day (YYYYMMDD)
fn getCurrentDay() i64 {
    const timestamp = std.time.timestamp();
    const epoch_day = @divFloor(timestamp, 86400);
    return epoch_day;
}

/// Get current month (YYYYMM)
fn getCurrentMonth() i64 {
    const timestamp = std.time.timestamp();
    const epoch_day = @divFloor(timestamp, 86400);
    const epoch_month = @divFloor(epoch_day, 30); // Approximate
    return epoch_month;
}

// Tests
test "cost tracker basic operations" {
    var tracker = try CostTracker.init(std.testing.allocator, .{});
    defer tracker.deinit();

    // Record free request
    try tracker.recordRequest(.ollama, 1000, 500);
    const usage = tracker.getUsage(.ollama).?;
    try std.testing.expectEqual(@as(u64, 1), usage.total_requests);
    try std.testing.expectEqual(@as(f64, 0.0), usage.total_cost);
}

test "cost calculation for token-based pricing" {
    var tracker = try CostTracker.init(std.testing.allocator, .{});
    defer tracker.deinit();

    // Claude: $3/1M input, $15/1M output
    // 1000 input + 500 output = $0.003 + $0.0075 = $0.0105
    try tracker.recordRequest(.anthropic, 1000, 500);

    const usage = tracker.getUsage(.anthropic).?;
    try std.testing.expectApproxEqRel(@as(f64, 0.0105), usage.total_cost, 0.0001);
}

test "budget enforcement" {
    var tracker = try CostTracker.init(std.testing.allocator, .{
        .enabled = true,
        .daily_limit_usd = 1.0,
        .monthly_limit_usd = 10.0,
    });
    defer tracker.deinit();

    // Can afford small request
    try std.testing.expect(tracker.canAfford(.anthropic, 10000));

    // Simulate expensive requests
    try tracker.recordRequest(.anthropic, 100_000, 100_000); // ~$1.80

    // Should not afford more
    try std.testing.expect(!tracker.canAfford(.anthropic, 10000));
}

test "budget warnings" {
    var tracker = try CostTracker.init(std.testing.allocator, .{
        .enabled = true,
        .daily_limit_usd = 1.0,
        .warn_at_percent = 80.0,
        .pause_at_percent = 95.0,
    });
    defer tracker.deinit();

    // Below warning threshold
    try tracker.recordRequest(.anthropic, 10_000, 10_000); // ~$0.30
    try std.testing.expect(!tracker.shouldWarnBudget());

    // Above warning threshold
    try tracker.recordRequest(.anthropic, 30_000, 30_000); // Total ~$0.90
    try std.testing.expect(tracker.shouldWarnBudget());
    try std.testing.expect(!tracker.shouldPauseBudget());
}

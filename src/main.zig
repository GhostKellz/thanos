const std = @import("std");
const thanos_lib = @import("thanos");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "discover")) {
        try discoverCommand(allocator);
    } else if (std.mem.eql(u8, command, "complete")) {
        if (args.len < 3) {
            std.debug.print("Usage: thanos complete <prompt>\n", .{});
            return;
        }
        try completeCommand(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "stats")) {
        try statsCommand(allocator);
    } else if (std.mem.eql(u8, command, "health")) {
        try healthCommand(allocator);
    } else if (std.mem.eql(u8, command, "cost")) {
        try costCommand(allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Thanos v0.1.0 - Unified AI Infrastructure Gateway\n", .{});
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    std.debug.print(
        \\Thanos - Unified AI Infrastructure Integration Layer
        \\
        \\Usage: thanos [options] <command> [args]
        \\
        \\Options:
        \\  --config, -c <path>    Path to configuration file (default: ./thanos.toml)
        \\
        \\Commands:
        \\  discover    Discover available AI providers
        \\  complete    Complete a prompt using auto-routing
        \\  stats       Show Thanos statistics
        \\  health      Show provider health status
        \\  cost        Show cost tracking and budget status
        \\  version     Show version information
        \\
        \\Examples:
        \\  thanos --config ~/.config/thanos/thanos.toml discover
        \\  thanos complete "fn main() "
        \\  thanos stats
        \\  thanos health
        \\  thanos cost
        \\
    , .{});
}

fn loadConfigWithFallback(allocator: std.mem.Allocator) !thanos_lib.Config {
    // Try to load from ./thanos.toml first
    const config = thanos_lib.config.loadConfig(allocator, "thanos.toml") catch |err| {
        std.debug.print("[Config] Using default configuration ({s})\n", .{@errorName(err)});
        return thanos_lib.Config{
            .debug = true,
        };
    };
    return config;
}

fn discoverCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🌌 Thanos - Discovering AI Providers\n\n", .{});

    const config = try loadConfigWithFallback(allocator);

    var thanos = try thanos_lib.Thanos.init(allocator, config);
    defer thanos.deinit();

    const providers = try thanos.listProviders();
    defer allocator.free(providers);

    std.debug.print("\n📊 Discovery Results:\n", .{});
    if (providers.len == 0) {
        std.debug.print("  ❌ No providers available\n", .{});
    } else {
        for (providers) |provider_health| {
            const status = if (provider_health.available) "✅ Available" else "❌ Unavailable";
            std.debug.print("  {s}: {s}\n", .{ provider_health.provider.toString(), status });

            if (provider_health.latency_ms) |latency| {
                std.debug.print("     Latency: {}ms\n", .{latency});
            }
        }
    }
}

fn completeCommand(allocator: std.mem.Allocator, prompt: []const u8) !void {
    std.debug.print("🌌 Thanos - AI Completion\n\n", .{});

    const config = try loadConfigWithFallback(allocator);

    var thanos = try thanos_lib.Thanos.init(allocator, config);
    defer thanos.deinit();

    const request = thanos_lib.CompletionRequest{
        .prompt = prompt,
        .language = "zig",
        .max_tokens = 100,
    };

    std.debug.print("Prompt: {s}\n", .{prompt});
    std.debug.print("Routing...\n\n", .{});

    const response = try thanos.complete(request);
    defer response.deinit(allocator);

    if (response.success) {
        std.debug.print("✅ Success ({s}, {}ms)\n", .{ response.provider.toString(), response.latency_ms });
        std.debug.print("Completion:\n{s}\n", .{response.text});
    } else {
        std.debug.print("❌ Failed: {s}\n", .{response.error_message orelse "Unknown error"});
    }
}

fn statsCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🌌 Thanos Statistics\n\n", .{});

    const config = try loadConfigWithFallback(allocator);

    var thanos = try thanos_lib.Thanos.init(allocator, config);
    defer thanos.deinit();

    const stats = try thanos.getStats();

    std.debug.print("Providers Available: {}\n", .{stats.providers_available});
    std.debug.print("Total Requests: {}\n", .{stats.total_requests});
    std.debug.print("Avg Latency: {}ms\n", .{stats.avg_latency_ms});
}

fn healthCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🏥 Provider Health Status\n\n", .{});

    const config = try loadConfigWithFallback(allocator);

    var thanos = try thanos_lib.Thanos.init(allocator, config);
    defer thanos.deinit();

    const health_report = try thanos.getHealthReport();
    defer allocator.free(health_report);

    std.debug.print("{s}\n", .{health_report});
}

fn costCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("💰 Cost Tracking & Budget Status\n\n", .{});

    const config = try loadConfigWithFallback(allocator);

    var thanos = try thanos_lib.Thanos.init(allocator, config);
    defer thanos.deinit();

    const cost_report = try thanos.getCostReport();
    defer allocator.free(cost_report);

    std.debug.print("{s}\n", .{cost_report});

    // Show budget usage
    const budget_usage = thanos.getBudgetUsage();
    std.debug.print("\n📊 Budget Usage:\n", .{});
    std.debug.print("  Daily: {d:.1}%\n", .{budget_usage.daily});
    std.debug.print("  Monthly: {d:.1}%\n", .{budget_usage.monthly});
}

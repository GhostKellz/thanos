// Basic Completion Example
// Demonstrates a simple completion request using Thanos

const std = @import("std");
const thanos = @import("thanos");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🌌 Thanos Basic Completion Example\n\n", .{});

    // Initialize Thanos with default config
    const config = thanos.Config{
        .debug = true,
    };

    var ai = try thanos.Thanos.init(allocator, config);
    defer ai.deinit();

    // Create a completion request
    const request = thanos.CompletionRequest{
        .prompt = "Write a Zig function to calculate fibonacci numbers",
        .max_tokens = 500,
        .temperature = 0.7,
    };

    std.debug.print("📝 Prompt: {s}\n\n", .{request.prompt});
    std.debug.print("⏳ Generating completion...\n\n", .{});

    // Get completion
    const response = try ai.complete(request);
    defer response.deinit(allocator);

    // Print results
    if (response.success) {
        std.debug.print("✅ Success!\n", .{});
        std.debug.print("Provider: {s}\n", .{response.provider.toString()});
        std.debug.print("Latency: {}ms\n", .{response.latency_ms});
        std.debug.print("Confidence: {d:.2}\n\n", .{response.confidence});
        std.debug.print("Response:\n{s}\n", .{response.text});
    } else {
        std.debug.print("❌ Error: {s}\n", .{response.error_message orelse "Unknown error"});
        return error.CompletionFailed;
    }

    // Show statistics
    const stats = try ai.getStats();
    std.debug.print("\n📊 Statistics:\n", .{});
    std.debug.print("  Providers available: {}\n", .{stats.providers_available});
    std.debug.print("  Total requests: {}\n", .{stats.total_requests});
    std.debug.print("  Avg latency: {}ms\n", .{stats.avg_latency_ms});
}

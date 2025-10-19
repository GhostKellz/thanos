const std = @import("std");
const thanos = @import("thanos");

// Streaming callback function
fn streamCallback(chunk: []const u8, user_data: ?*anyopaque) void {
    _ = user_data;
    // Print each chunk as it arrives
    std.debug.print("{s}", .{chunk});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🌊 Thanos Streaming Example\n\n", .{});

    // Initialize Thanos with debug mode
    const config = thanos.types.Config{
        .debug = true,
    };

    var ai = try thanos.Thanos.init(allocator, config);
    defer ai.deinit();

    std.debug.print("\n📝 Streaming completion:\n", .{});
    std.debug.print("---\n", .{});

    // Create streaming request
    const request = thanos.types.StreamingCompletionRequest{
        .prompt = "Write a Zig function to calculate fibonacci numbers. Keep it concise.",
        .max_tokens = 200,
        .temperature = 0.7,
        .callback = streamCallback,
        .user_data = null,
    };

    // Start streaming
    const response = try ai.completeStreaming(request);
    defer response.deinit(allocator);

    std.debug.print("\n---\n", .{});

    if (response.success) {
        std.debug.print("\n✅ Streaming complete!\n", .{});
        std.debug.print("Provider: {s}\n", .{response.provider.toString()});
        std.debug.print("Total tokens: {}\n", .{response.total_tokens});
        std.debug.print("Latency: {}ms\n", .{response.latency_ms});
    } else {
        std.debug.print("\n❌ Streaming failed: {s}\n", .{response.error_message orelse "Unknown error"});
    }
}

// Cache Performance Benchmark
// Measures LRU cache performance

const std = @import("std");
const cache = @import("thanos").cache;

const ITERATIONS = 100_000;
const CACHE_SIZE = 1000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔬 Thanos Cache Benchmark\n\n", .{});

    // Initialize cache
    var response_cache = try cache.ResponseCache.init(allocator, CACHE_SIZE, 3600);
    defer response_cache.deinit();

    // Benchmark: Cache Insertions
    std.debug.print("📊 Benchmark 1: Cache Insertions ({} items)\n", .{ITERATIONS});
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < ITERATIONS) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator, "prompt_{}", .{i});
        defer allocator.free(key);

        const response = cache.types.CompletionResponse{
            .text = "Sample response",
            .provider = .ollama,
            .latency_ms = 100,
            .success = true,
        };

        try response_cache.put(key, response);
    }

    const insert_time = timer.read();
    const insert_per_op = insert_time / ITERATIONS;

    std.debug.print("  Total time: {d:.2}ms\n", .{@as(f64, @floatFromInt(insert_time)) / 1_000_000.0});
    std.debug.print("  Per insert: {d:.3}µs\n", .{@as(f64, @floatFromInt(insert_per_op)) / 1_000.0});
    std.debug.print("  Throughput: {d:.0} inserts/sec\n\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(insert_per_op))});

    // Benchmark: Cache Lookups (hits)
    std.debug.print("📊 Benchmark 2: Cache Lookups - Hits ({} lookups)\n", .{ITERATIONS});
    timer.reset();

    var hits: usize = 0;
    i = 0;
    while (i < ITERATIONS) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator, "prompt_{}", .{i % CACHE_SIZE});
        defer allocator.free(key);

        if (response_cache.get(key)) |resp| {
            defer allocator.free(resp.text);
            hits += 1;
        }
    }

    const lookup_time = timer.read();
    const lookup_per_op = lookup_time / ITERATIONS;

    std.debug.print("  Total time: {d:.2}ms\n", .{@as(f64, @floatFromInt(lookup_time)) / 1_000_000.0});
    std.debug.print("  Per lookup: {d:.3}µs\n", .{@as(f64, @floatFromInt(lookup_per_op)) / 1_000.0});
    std.debug.print("  Hit rate: {d:.1}%\n", .{@as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(ITERATIONS)) * 100.0});
    std.debug.print("  Throughput: {d:.0} lookups/sec\n\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(lookup_per_op))});

    // Benchmark: Cache Lookups (misses)
    std.debug.print("📊 Benchmark 3: Cache Lookups - Misses ({} lookups)\n", .{ITERATIONS});
    timer.reset();

    var misses: usize = 0;
    i = 0;
    while (i < ITERATIONS) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator, "missing_{}", .{i});
        defer allocator.free(key);

        if (response_cache.get(key)) |resp| {
            defer allocator.free(resp.text);
        } else {
            misses += 1;
        }
    }

    const miss_time = timer.read();
    const miss_per_op = miss_time / ITERATIONS;

    std.debug.print("  Total time: {d:.2}ms\n", .{@as(f64, @floatFromInt(miss_time)) / 1_000_000.0});
    std.debug.print("  Per lookup: {d:.3}µs\n", .{@as(f64, @floatFromInt(miss_per_op)) / 1_000.0});
    std.debug.print("  Miss rate: {d:.1}%\n", .{@as(f64, @floatFromInt(misses)) / @as(f64, @floatFromInt(ITERATIONS)) * 100.0});
    std.debug.print("  Throughput: {d:.0} lookups/sec\n\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(miss_per_op))});

    // Show cache statistics
    const stats = response_cache.getStats();
    std.debug.print("📈 Cache Statistics:\n", .{});
    std.debug.print("  Total hits: {}\n", .{stats.hits});
    std.debug.print("  Total misses: {}\n", .{stats.misses});
    std.debug.print("  Hit rate: {d:.1}%\n", .{@as(f64, @floatFromInt(stats.hits)) / @as(f64, @floatFromInt(stats.hits + stats.misses)) * 100.0});
    std.debug.print("  Evictions: {}\n", .{stats.evictions});
}

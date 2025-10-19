//! C ABI interface for Thanos plugins
//!
//! Provides a stable C-compatible API for Neovim/Grim plugins to interface with Thanos.
//! This allows both Lua (via FFI) and native Zig code to use Thanos functionality.

const std = @import("std");
const thanos_root = @import("thanos");
const Thanos = thanos_root.Thanos;
const types = thanos_root.types;

// ============================================================================
// Global State Management
// ============================================================================

/// Global allocator for plugin (uses C allocator for compatibility)
var plugin_allocator: std.mem.Allocator = undefined;

/// Global Thanos instance
var plugin_thanos: ?*Thanos = null;

/// Initialization flag
var is_initialized: bool = false;

// ============================================================================
// Initialization & Cleanup
// ============================================================================

/// Initialize Thanos plugin with JSON configuration
///
/// Example config_json:
/// {
///   "debug": true,
///   "omen_endpoint": "http://localhost:3000",
///   "ollama_endpoint": "http://localhost:11434",
///   "bolt_grpc_endpoint": "127.0.0.1:50051"
/// }
///
/// Returns: 1 on success, 0 on failure
export fn thanos_init(config_json: ?[*:0]const u8) c_int {
    if (is_initialized) {
        return 1; // Already initialized
    }

    plugin_allocator = std.heap.c_allocator;

    // Parse config or use defaults
    const config = parseConfig(config_json) catch types.Config{
        .debug = true, // Enable debug by default for plugins
    };

    // Create Thanos instance
    const t = plugin_allocator.create(Thanos) catch {
        return 0;
    };

    t.* = Thanos.init(plugin_allocator, config) catch {
        plugin_allocator.destroy(t);
        return 0;
    };

    plugin_thanos = t;
    is_initialized = true;

    return 1;
}

/// Cleanup and free all resources
export fn thanos_deinit() void {
    if (plugin_thanos) |t| {
        t.deinit();
        plugin_allocator.destroy(t);
        plugin_thanos = null;
    }
    is_initialized = false;
}

// ============================================================================
// Completion API
// ============================================================================

/// Complete a prompt with AI
///
/// Args:
///   - prompt: The text to complete (null-terminated)
///   - language: Optional language hint (e.g., "zig", "rust", null for auto-detect)
///   - max_tokens: Maximum tokens to generate (0 = default)
///
/// Returns: Null-terminated completion text (caller must free with thanos_free_string)
///          Returns NULL on error
export fn thanos_complete(
    prompt: [*:0]const u8,
    language: ?[*:0]const u8,
    max_tokens: c_int,
) ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const lang = if (language) |l| std.mem.span(l) else null;
    const max_tok = if (max_tokens > 0) @as(u32, @intCast(max_tokens)) else null;

    const request = types.CompletionRequest{
        .prompt = std.mem.span(prompt),
        .language = lang,
        .max_tokens = max_tok,
        .provider = null, // Auto-route
    };

    const response = t.complete(request) catch return null;
    defer response.deinit(plugin_allocator);

    if (!response.success) {
        return null;
    }

    // Duplicate string with null terminator for C
    const result = plugin_allocator.dupeZ(u8, response.text) catch return null;
    return result.ptr;
}

/// Complete with specific provider
///
/// provider_name: "omen", "ollama", "anthropic", "openai"
export fn thanos_complete_with_provider(
    prompt: [*:0]const u8,
    provider_name: [*:0]const u8,
    language: ?[*:0]const u8,
    max_tokens: c_int,
) ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const provider = parseProvider(std.mem.span(provider_name)) orelse return null;
    const lang = if (language) |l| std.mem.span(l) else null;
    const max_tok = if (max_tokens > 0) @as(u32, @intCast(max_tokens)) else null;

    const request = types.CompletionRequest{
        .prompt = std.mem.span(prompt),
        .language = lang,
        .max_tokens = max_tok,
        .provider = provider,
    };

    const response = t.complete(request) catch return null;
    defer response.deinit(plugin_allocator);

    if (!response.success) {
        return null;
    }

    const result = plugin_allocator.dupeZ(u8, response.text) catch return null;
    return result.ptr;
}

// ============================================================================
// Tool Execution API
// ============================================================================

/// Execute an MCP tool
///
/// Args:
///   - tool_name: Name of the tool (e.g., "read_file", "write_file", "bash")
///   - args_json: JSON arguments for the tool
///
/// Returns: JSON result string (caller must free with thanos_free_string)
///          Returns NULL on error
export fn thanos_execute_tool(
    tool_name: [*:0]const u8,
    args_json: [*:0]const u8,
) ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    // TODO: Parse JSON arguments properly
    _ = args_json;

    const request = types.ToolRequest{
        .tool_name = std.mem.span(tool_name),
        .arguments = .{ .null = {} }, // Placeholder
    };

    const response = t.executeTool(request) catch return null;
    defer response.deinit(plugin_allocator);

    if (!response.success) {
        return null;
    }

    // TODO: Serialize result to JSON
    const result = plugin_allocator.dupeZ(u8, "{}") catch return null;
    return result.ptr;
}

// ============================================================================
// Provider Management API
// ============================================================================

/// List available providers as JSON array
///
/// Returns: JSON string like:
/// [
///   {"name": "omen", "available": true, "latency_ms": 50},
///   {"name": "ollama", "available": true, "latency_ms": 20}
/// ]
export fn thanos_list_providers() ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const providers = t.listProviders() catch return null;
    defer plugin_allocator.free(providers);

    // Serialize to JSON
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(plugin_allocator);

    json_buf.appendSlice(plugin_allocator, "[") catch return null;

    for (providers, 0..) |provider, i| {
        if (i > 0) {
            json_buf.appendSlice(plugin_allocator, ",") catch return null;
        }

        const entry = std.fmt.allocPrint(
            plugin_allocator,
            \\{{"name":"{s}","available":{s}}}
        ,
            .{
                provider.provider.toString(),
                if (provider.available) "true" else "false",
            },
        ) catch return null;
        defer plugin_allocator.free(entry);

        json_buf.appendSlice(plugin_allocator, entry) catch return null;
    }

    json_buf.appendSlice(plugin_allocator, "]") catch return null;

    const result = json_buf.toOwnedSliceSentinel(plugin_allocator, 0) catch return null;
    return result.ptr;
}

/// Get statistics as JSON
///
/// Returns: JSON like:
/// {"providers_available": 2, "total_requests": 42, "avg_latency_ms": 75}
export fn thanos_get_stats() ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const stats = t.getStats() catch return null;

    const json = std.fmt.allocPrint(
        plugin_allocator,
        \\{{"providers_available":{},"total_requests":{},"avg_latency_ms":{}}}
    ,
        .{
            stats.providers_available,
            stats.total_requests,
            stats.avg_latency_ms,
        },
    ) catch return null;

    // Add null terminator manually
    const json_z = plugin_allocator.dupeZ(u8, json) catch return null;
    plugin_allocator.free(json);

    return json_z.ptr;
}

// ============================================================================
// Health Monitoring API
// ============================================================================

/// Get health report for all providers
///
/// Returns: Health report as text (caller must free with thanos_free_string)
///          Returns NULL on error
export fn thanos_get_health_report() ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const report = t.getHealthReport() catch return null;
    defer plugin_allocator.free(report);

    const result = plugin_allocator.dupeZ(u8, report) catch return null;
    return result.ptr;
}

/// Check if a provider is healthy
///
/// provider_name: "omen", "ollama", "anthropic", "openai", etc.
/// Returns: 1 if healthy, 0 if unhealthy, -1 on error
export fn thanos_is_provider_healthy(provider_name: [*:0]const u8) c_int {
    const t = plugin_thanos orelse return -1;

    const provider = parseProvider(std.mem.span(provider_name)) orelse return -1;
    const is_healthy = t.isProviderHealthy(provider);

    return if (is_healthy) 1 else 0;
}

/// Get health data for all providers as JSON
///
/// Returns: JSON array of health check results
export fn thanos_get_all_health_json() ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const health_results = t.getAllHealth() catch return null;
    defer plugin_allocator.free(health_results);

    var parts: std.ArrayList([]const u8) = .{ .items = &[_][]const u8{}, .capacity = 0 };
    defer {
        for (parts.items) |part| {
            plugin_allocator.free(part);
        }
        parts.deinit(plugin_allocator);
    }

    parts.append(plugin_allocator, "[") catch return null;

    for (health_results, 0..) |result, i| {
        if (i > 0) {
            parts.append(plugin_allocator, ",") catch return null;
        }

        const entry = std.fmt.allocPrint(
            plugin_allocator,
            \\{{"provider":"{s}","available":{s},"latency_ms":{},"success_rate":{d:.2}}}
        ,
            .{
                result.provider.toString(),
                if (result.available) "true" else "false",
                result.latency_ms,
                result.success_rate,
            },
        ) catch return null;

        parts.append(plugin_allocator, entry) catch return null;
    }

    parts.append(plugin_allocator, "]") catch return null;

    // Combine all parts
    var total_len: usize = 0;
    for (parts.items) |part| {
        total_len += part.len;
    }

    const combined = plugin_allocator.alloc(u8, total_len) catch return null;
    var pos: usize = 0;
    for (parts.items) |part| {
        @memcpy(combined[pos..][0..part.len], part);
        pos += part.len;
    }

    const result = plugin_allocator.dupeZ(u8, combined) catch return null;
    plugin_allocator.free(combined);
    return result.ptr;
}

// ============================================================================
// Cost Tracking API
// ============================================================================

/// Get cost report
///
/// Returns: Cost report as text (caller must free with thanos_free_string)
///          Returns NULL on error
export fn thanos_get_cost_report() ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const report = t.getCostReport() catch return null;
    defer plugin_allocator.free(report);

    const result = plugin_allocator.dupeZ(u8, report) catch return null;
    return result.ptr;
}

/// Get total cost
///
/// Returns: Total cost in USD (multiplied by 10000 to avoid floats in C API)
///          e.g., $12.34 = 123400
export fn thanos_get_total_cost() c_int {
    const t = plugin_thanos orelse return -1;

    const cost = t.getTotalCost();
    const cost_cents = @as(c_int, @intFromFloat(cost * 10000.0));

    return cost_cents;
}

/// Get budget usage as JSON
///
/// Returns: JSON like {"daily": 45.5, "monthly": 23.1}
export fn thanos_get_budget_usage_json() ?[*:0]u8 {
    const t = plugin_thanos orelse return null;

    const usage = t.getBudgetUsage();

    const json = std.fmt.allocPrint(
        plugin_allocator,
        \\{{"daily":{d:.1},"monthly":{d:.1}}}
    ,
        .{
            usage.daily,
            usage.monthly,
        },
    ) catch return null;

    const json_z = plugin_allocator.dupeZ(u8, json) catch return null;
    plugin_allocator.free(json);

    return json_z.ptr;
}

// ============================================================================
// Memory Management
// ============================================================================

/// Free a string allocated by Thanos
///
/// Must be called on all strings returned by Thanos functions
export fn thanos_free_string(str: [*:0]u8) void {
    plugin_allocator.free(std.mem.span(str));
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Get Thanos version string
export fn thanos_version() [*:0]const u8 {
    return "0.1.0";
}

/// Check if Thanos is initialized
export fn thanos_is_initialized() c_int {
    return if (is_initialized) 1 else 0;
}

/// Get last error message (if any)
///
/// Returns: Error message string or NULL if no error
export fn thanos_get_error() ?[*:0]const u8 {
    // TODO: Implement error tracking
    return null;
}

// ============================================================================
// Helper Functions (Internal)
// ============================================================================

fn parseConfig(json: ?[*:0]const u8) !types.Config {
    if (json == null) {
        return types.Config{};
    }

    // TODO: Implement proper JSON parsing
    // For now, return default config
    return types.Config{
        .debug = true,
    };
}

fn parseProvider(name: []const u8) ?types.Provider {
    if (std.mem.eql(u8, name, "omen")) return .omen;
    if (std.mem.eql(u8, name, "ollama")) return .ollama;
    if (std.mem.eql(u8, name, "anthropic")) return .anthropic;
    if (std.mem.eql(u8, name, "openai")) return .openai;
    return null;
}

// ============================================================================
// Test Exports (for debugging)
// ============================================================================

/// Simple ping function for testing C ABI
export fn thanos_ping() c_int {
    return 42;
}

/// Echo a string (for testing memory management)
export fn thanos_echo(input: [*:0]const u8) ?[*:0]u8 {
    const str = std.mem.span(input);
    const result = plugin_allocator.dupeZ(u8, str) catch return null;
    return result.ptr;
}

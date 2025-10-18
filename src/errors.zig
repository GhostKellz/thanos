//! Comprehensive error types for Thanos
//! Provides structured error handling with detailed context

const std = @import("std");
const types = @import("types.zig");

/// Thanos error set
pub const ThanosError = error{
    // Network errors
    NetworkTimeout,
    ConnectionRefused,
    ConnectionReset,
    InvalidResponse,
    StreamTooLong,
    UnexpectedEndOfStream,

    // Provider errors
    ProviderNotAvailable,
    ProviderNotConfigured,
    InvalidApiKey,
    RateLimitExceeded,
    QuotaExceeded,
    ServiceUnavailable,
    ModelNotFound,

    // Parsing errors
    JsonParseError,
    InvalidContentFormat,
    MissingRequiredField,
    InvalidFieldType,

    // Configuration errors
    ConfigFileNotFound,
    InvalidConfigFormat,
    EnvVarNotFound,
    InvalidProviderName,

    // Request errors
    InvalidPrompt,
    PromptTooLong,
    MaxTokensExceeded,
    InvalidTemperature,

    // Cache errors
    CacheCorrupted,
    CacheExpired,
    CacheFull,

    // General errors
    OutOfMemory,
    Unknown,
};

/// Detailed provider error with context
pub const ProviderError = struct {
    provider: types.Provider,
    error_type: ThanosError,
    message: []const u8,
    http_status: ?u16 = null,
    retry_after: ?u32 = null, // seconds
    request_id: ?[]const u8 = null,

    /// Check if error is retryable
    pub fn isRetryable(self: ProviderError) bool {
        return switch (self.error_type) {
            error.NetworkTimeout,
            error.ConnectionRefused,
            error.ConnectionReset,
            error.ServiceUnavailable,
            error.RateLimitExceeded,
            => true,
            else => false,
        };
    }

    /// Get recommended retry delay in milliseconds
    pub fn getRetryDelay(self: ProviderError, attempt: u32) u32 {
        // If server specifies retry-after, use it
        if (self.retry_after) |seconds| {
            return seconds * 1000;
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, ...
        const base_delay = std.math.pow(u32, 2, attempt) * 1000;
        const max_delay = 60000; // Cap at 60 seconds
        return @min(base_delay, max_delay);
    }

    /// Format error for display
    pub fn format(
        self: ProviderError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{s}] {s}: {s}", .{
            self.provider.toString(),
            @errorName(self.error_type),
            self.message,
        });

        if (self.http_status) |status| {
            try writer.print(" (HTTP {})", .{status});
        }

        if (self.retry_after) |seconds| {
            try writer.print(" - Retry after {}s", .{seconds});
        }

        if (self.request_id) |id| {
            try writer.print(" [Request ID: {s}]", .{id});
        }
    }
};

/// Network error with timing information
pub const NetworkError = struct {
    error_type: ThanosError,
    endpoint: []const u8,
    elapsed_ms: u32,
    message: []const u8,

    pub fn format(
        self: NetworkError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Network error after {}ms to {s}: {s} - {s}", .{
            self.elapsed_ms,
            self.endpoint,
            @errorName(self.error_type),
            self.message,
        });
    }
};

/// Configuration error with file context
pub const ConfigError = struct {
    error_type: ThanosError,
    file_path: []const u8,
    line: ?u32 = null,
    column: ?u32 = null,
    message: []const u8,

    pub fn format(
        self: ConfigError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Config error in {s}", .{self.file_path});

        if (self.line) |line| {
            try writer.print(" at line {}", .{line});
            if (self.column) |col| {
                try writer.print(":{}", .{col});
            }
        }

        try writer.print(": {s} - {s}", .{
            @errorName(self.error_type),
            self.message,
        });
    }
};

/// Convert HTTP status code to ThanosError
pub fn httpStatusToError(status: u16) ThanosError {
    return switch (status) {
        401, 403 => error.InvalidApiKey,
        404 => error.ModelNotFound,
        429 => error.RateLimitExceeded,
        500, 502, 503, 504 => error.ServiceUnavailable,
        else => error.InvalidResponse,
    };
}

/// Parse Retry-After header value (seconds or HTTP date)
pub fn parseRetryAfter(header_value: []const u8) ?u32 {
    // Try parsing as seconds first
    const seconds = std.fmt.parseInt(u32, header_value, 10) catch {
        // Could parse HTTP date here if needed
        return null;
    };
    return seconds;
}

/// Create a ProviderError from HTTP response
pub fn fromHttpError(
    allocator: std.mem.Allocator,
    provider: types.Provider,
    status: u16,
    response_body: []const u8,
) !ProviderError {
    const error_type = httpStatusToError(status);

    // Try to extract error message from response body
    const message = try extractErrorMessage(allocator, response_body);

    return ProviderError{
        .provider = provider,
        .error_type = error_type,
        .message = message,
        .http_status = status,
    };
}

/// Extract error message from JSON response body
fn extractErrorMessage(allocator: std.mem.Allocator, json: []const u8) ![]const u8 {
    // Try common error message patterns
    const patterns = [_][]const u8{
        "\"error\":{\"message\":\"",
        "\"error\":\"",
        "\"message\":\"",
        "\"detail\":\"",
    };

    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, json, pattern)) |start_idx| {
            const value_start = start_idx + pattern.len;
            const remaining = json[value_start..];

            // Find closing quote (handle escaped quotes)
            var end_idx: usize = 0;
            var escaped = false;
            for (remaining, 0..) |char, i| {
                if (escaped) {
                    escaped = false;
                    continue;
                }
                if (char == '\\') {
                    escaped = true;
                    continue;
                }
                if (char == '"') {
                    end_idx = i;
                    break;
                }
            }

            if (end_idx > 0) {
                return try allocator.dupe(u8, remaining[0..end_idx]);
            }
        }
    }

    // Fallback to generic message
    return try allocator.dupe(u8, "Unknown error");
}

/// Error context for debugging
pub const ErrorContext = struct {
    timestamp: i64,
    provider: ?types.Provider = null,
    endpoint: ?[]const u8 = null,
    request_prompt: ?[]const u8 = null,
    error_chain: []const []const u8,

    pub fn init(allocator: std.mem.Allocator) ErrorContext {
        _ = allocator;
        return ErrorContext{
            .timestamp = std.time.timestamp(),
            .error_chain = &.{},
        };
    }

    pub fn addError(self: *ErrorContext, allocator: std.mem.Allocator, err_msg: []const u8) !void {
        var new_chain = try allocator.alloc([]const u8, self.error_chain.len + 1);
        for (self.error_chain, 0..) |msg, i| {
            new_chain[i] = msg;
        }
        new_chain[self.error_chain.len] = try allocator.dupe(u8, err_msg);

        if (self.error_chain.len > 0) {
            allocator.free(self.error_chain);
        }
        self.error_chain = new_chain;
    }

    pub fn deinit(self: *ErrorContext, allocator: std.mem.Allocator) void {
        for (self.error_chain) |msg| {
            allocator.free(msg);
        }
        if (self.error_chain.len > 0) {
            allocator.free(self.error_chain);
        }
    }

    pub fn print(self: ErrorContext) void {
        std.debug.print("\n=== Error Context ===\n", .{});
        std.debug.print("Timestamp: {}\n", .{self.timestamp});

        if (self.provider) |provider| {
            std.debug.print("Provider: {s}\n", .{provider.toString()});
        }

        if (self.endpoint) |endpoint| {
            std.debug.print("Endpoint: {s}\n", .{endpoint});
        }

        if (self.request_prompt) |prompt| {
            const truncated = if (prompt.len > 100) prompt[0..100] else prompt;
            std.debug.print("Prompt: {s}...\n", .{truncated});
        }

        if (self.error_chain.len > 0) {
            std.debug.print("\nError chain:\n", .{});
            for (self.error_chain, 0..) |err, i| {
                std.debug.print("  {}. {s}\n", .{ i + 1, err });
            }
        }
        std.debug.print("==================\n\n", .{});
    }
};

//! Retry logic with exponential backoff for transient failures
//! Handles network timeouts, rate limits, and temporary service issues

const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

/// Retry configuration
pub const RetryConfig = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u32 = 1000, // 1 second
    max_delay_ms: u32 = 60000, // 60 seconds
    backoff_multiplier: f32 = 2.0,
    jitter: bool = true, // Add randomness to prevent thundering herd

    /// Calculate delay for a given attempt
    pub fn getDelay(self: RetryConfig, attempt: u32) u32 {
        // Exponential backoff: initial_delay * (multiplier ^ attempt)
        const base_delay = @as(f32, @floatFromInt(self.initial_delay_ms)) *
            std.math.pow(f32, self.backoff_multiplier, @as(f32, @floatFromInt(attempt)));

        var delay = @min(@as(u32, @intFromFloat(base_delay)), self.max_delay_ms);

        // Add jitter (±25% randomness)
        if (self.jitter) {
            var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
            const random = prng.random();
            const jitter_range = delay / 4; // 25%
            const jitter_offset = random.intRangeAtMost(i32, -@as(i32, @intCast(jitter_range)), @as(i32, @intCast(jitter_range)));
            delay = @intCast(@as(i32, @intCast(delay)) + jitter_offset);
        }

        return delay;
    }

    /// Check if error is retryable
    pub fn isRetryable(err: anyerror) bool {
        return switch (err) {
            error.NetworkTimeout,
            error.ConnectionRefused,
            error.ConnectionReset,
            error.ServiceUnavailable,
            error.RateLimitExceeded,
            error.StreamTooLong,
            error.UnexpectedEndOfStream,
            => true,
            else => false,
        };
    }
};

/// Retry context tracking attempt history
pub const RetryContext = struct {
    attempt: u32 = 0,
    total_delay_ms: u32 = 0,
    last_error: ?anyerror = null,
    start_time: i64,

    pub fn init() RetryContext {
        return RetryContext{
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn recordAttempt(self: *RetryContext, delay_ms: u32, err: ?anyerror) void {
        self.attempt += 1;
        self.total_delay_ms += delay_ms;
        self.last_error = err;
    }

    pub fn getTotalElapsed(self: RetryContext) u32 {
        const now = std.time.milliTimestamp();
        return @intCast(now - self.start_time);
    }
};

/// Execute function with retry logic
pub fn withRetry(
    comptime ResultType: type,
    comptime func: fn () anyerror!ResultType,
    config: RetryConfig,
) !ResultType {
    var context = RetryContext.init();
    var attempt: u32 = 0;

    while (attempt < config.max_attempts) : (attempt += 1) {
        const result = func() catch |err| {
            // Check if error is retryable
            if (!config.isRetryable(err)) {
                return err;
            }

            // If this was the last attempt, return the error
            if (attempt + 1 >= config.max_attempts) {
                return err;
            }

            // Calculate delay and wait
            const delay_ms = config.getDelay(attempt);
            context.recordAttempt(delay_ms, err);

            std.debug.print(
                "[Retry] Attempt {}/{} failed with {s}, retrying in {}ms...\n",
                .{ attempt + 1, config.max_attempts, @errorName(err), delay_ms },
            );

            std.time.sleep(delay_ms * std.time.ns_per_ms);
            continue;
        };

        // Success!
        if (attempt > 0) {
            std.debug.print(
                "[Retry] Success after {} attempts (total delay: {}ms)\n",
                .{ attempt + 1, context.total_delay_ms },
            );
        }
        return result;
    }

    // Should not reach here
    return context.last_error orelse error.Unknown;
}

/// Retry wrapper for completion requests
pub fn retryCompletion(
    comptime ClientType: type,
    client: *ClientType,
    request: types.CompletionRequest,
    config: RetryConfig,
) !types.CompletionResponse {
    var context = RetryContext.init();
    var attempt: u32 = 0;

    while (attempt < config.max_attempts) : (attempt += 1) {
        const result = client.complete(request) catch |err| {
            // Check if error is retryable
            if (!config.isRetryable(err)) {
                return err;
            }

            // If this was the last attempt, return the error
            if (attempt + 1 >= config.max_attempts) {
                return err;
            }

            // Calculate delay and wait
            const delay_ms = config.getDelay(attempt);
            context.recordAttempt(delay_ms, err);

            if (request.provider) |provider| {
                std.debug.print(
                    "[Retry] [{s}] Attempt {}/{} failed with {s}, retrying in {}ms...\n",
                    .{ provider.toString(), attempt + 1, config.max_attempts, @errorName(err), delay_ms },
                );
            } else {
                std.debug.print(
                    "[Retry] Attempt {}/{} failed with {s}, retrying in {}ms...\n",
                    .{ attempt + 1, config.max_attempts, @errorName(err), delay_ms },
                );
            }

            std.time.sleep(delay_ms * std.time.ns_per_ms);
            continue;
        };

        // Success!
        if (attempt > 0 and request.provider != null) {
            std.debug.print(
                "[Retry] [{s}] Success after {} attempts (total delay: {}ms)\n",
                .{ request.provider.?.toString(), attempt + 1, context.total_delay_ms },
            );
        }
        return result;
    }

    // Should not reach here
    return context.last_error orelse error.Unknown;
}

/// Adaptive retry - adjusts based on error type
pub const AdaptiveRetryConfig = struct {
    base_config: RetryConfig,

    pub fn init() AdaptiveRetryConfig {
        return AdaptiveRetryConfig{
            .base_config = RetryConfig{},
        };
    }

    /// Get retry config adjusted for specific error
    pub fn getConfigForError(self: AdaptiveRetryConfig, err: anyerror) RetryConfig {
        var config = self.base_config;

        switch (err) {
            error.RateLimitExceeded => {
                // Longer delays for rate limits
                config.initial_delay_ms = 5000; // 5 seconds
                config.max_delay_ms = 120000; // 2 minutes
                config.backoff_multiplier = 3.0;
            },
            error.ServiceUnavailable => {
                // Moderate delays for service issues
                config.initial_delay_ms = 2000; // 2 seconds
                config.max_delay_ms = 30000; // 30 seconds
            },
            error.NetworkTimeout => {
                // Quick retries for timeouts
                config.initial_delay_ms = 500; // 0.5 seconds
                config.max_delay_ms = 10000; // 10 seconds
                config.max_attempts = 5; // More attempts
            },
            else => {},
        }

        return config;
    }
};

/// Circuit breaker pattern to prevent cascading failures
pub const CircuitBreaker = struct {
    allocator: std.mem.Allocator,
    failure_threshold: u32,
    timeout_ms: u32,
    consecutive_failures: u32 = 0,
    state: State = .closed,
    opened_at: ?i64 = null,

    pub const State = enum {
        closed, // Normal operation
        open, // Blocking requests
        half_open, // Testing if service recovered
    };

    pub fn init(allocator: std.mem.Allocator, failure_threshold: u32, timeout_ms: u32) CircuitBreaker {
        return CircuitBreaker{
            .allocator = allocator,
            .failure_threshold = failure_threshold,
            .timeout_ms = timeout_ms,
        };
    }

    /// Check if request should be allowed
    pub fn allowRequest(self: *CircuitBreaker) bool {
        switch (self.state) {
            .closed => return true,
            .half_open => return true,
            .open => {
                // Check if timeout has elapsed
                const now = std.time.milliTimestamp();
                if (self.opened_at) |opened| {
                    if (now - opened > self.timeout_ms) {
                        self.state = .half_open;
                        return true;
                    }
                }
                return false;
            },
        }
    }

    /// Record successful request
    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.consecutive_failures = 0;
        if (self.state == .half_open) {
            self.state = .closed;
            std.debug.print("[CircuitBreaker] Closed - service recovered\n", .{});
        }
    }

    /// Record failed request
    pub fn recordFailure(self: *CircuitBreaker) void {
        self.consecutive_failures += 1;

        if (self.consecutive_failures >= self.failure_threshold) {
            self.state = .open;
            self.opened_at = std.time.milliTimestamp();
            std.debug.print(
                "[CircuitBreaker] Opened after {} consecutive failures\n",
                .{self.consecutive_failures},
            );
        }
    }

    /// Get current state
    pub fn getState(self: CircuitBreaker) State {
        return self.state;
    }

    /// Reset circuit breaker
    pub fn reset(self: *CircuitBreaker) void {
        self.consecutive_failures = 0;
        self.state = .closed;
        self.opened_at = null;
    }
};

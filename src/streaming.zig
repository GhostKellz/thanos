//! Streaming support for real-time AI responses
//! Implements SSE (Server-Sent Events) for chunk-by-chunk delivery
const std = @import("std");
const types = @import("types.zig");

/// Stream state
pub const StreamState = enum {
    idle,
    connecting,
    streaming,
    completed,
    error_occurred,
    cancelled,
};

/// Streaming session
pub const StreamSession = struct {
    allocator: std.mem.Allocator,
    state: StreamState,
    provider: types.Provider,
    callback: types.StreamCallback,
    user_data: ?*anyopaque,
    total_tokens: u32 = 0,
    chunks_received: u32 = 0,
    start_time: i64,
    error_message: ?[]const u8 = null,
    cancelled: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        provider: types.Provider,
        callback: types.StreamCallback,
        user_data: ?*anyopaque,
    ) StreamSession {
        return .{
            .allocator = allocator,
            .state = .idle,
            .provider = provider,
            .callback = callback,
            .user_data = user_data,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *StreamSession) void {
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Process a chunk from the stream
    pub fn processChunk(self: *StreamSession, chunk: []const u8) void {
        if (self.cancelled) return;

        self.chunks_received += 1;
        self.state = .streaming;

        // Call user callback
        self.callback(chunk, self.user_data);
    }

    /// Mark stream as complete
    pub fn complete(self: *StreamSession) types.StreamingCompletionResponse {
        self.state = .completed;

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - self.start_time));

        return .{
            .provider = self.provider,
            .total_tokens = self.total_tokens,
            .latency_ms = latency,
            .success = true,
        };
    }

    /// Mark stream as error
    pub fn setError(self: *StreamSession, error_message: []const u8) !void {
        self.state = .error_occurred;

        if (self.error_message) |old_msg| {
            self.allocator.free(old_msg);
        }
        self.error_message = try self.allocator.dupe(u8, error_message);
    }

    /// Cancel the stream
    pub fn cancel(self: *StreamSession) void {
        self.cancelled = true;
        self.state = .cancelled;
    }
};

/// SSE (Server-Sent Events) parser
pub const SSEParser = struct {
    buffer: std.ArrayList(u8),
    event_type: ?[]const u8 = null,
    data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) SSEParser {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *SSEParser) void {
        self.buffer.deinit();
        self.data.deinit();
    }

    /// Parse SSE chunk
    /// Returns the data if a complete event is found
    pub fn parseChunk(self: *SSEParser, chunk: []const u8) !?[]const u8 {
        try self.buffer.appendSlice(chunk);

        // Look for complete event (double newline)
        if (std.mem.indexOf(u8, self.buffer.items, "\n\n")) |end_pos| {
            const event = self.buffer.items[0..end_pos];

            // Parse event
            var lines = std.mem.split(u8, event, "\n");
            self.data.clearRetainingCapacity();

            while (lines.next()) |line| {
                if (std.mem.startsWith(u8, line, "data: ")) {
                    const data_content = line[6..];
                    try self.data.appendSlice(data_content);
                    try self.data.append('\n');
                } else if (std.mem.startsWith(u8, line, "event: ")) {
                    self.event_type = line[7..];
                }
            }

            // Remove processed event from buffer
            const remaining = self.buffer.items[end_pos + 2 ..];
            const remaining_copy = try self.buffer.allocator.dupe(u8, remaining);
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(remaining_copy);
            self.buffer.allocator.free(remaining_copy);

            if (self.data.items.len > 0) {
                return self.data.items;
            }
        }

        return null;
    }

    /// Check if we received a completion signal
    pub fn isDone(self: *const SSEParser) bool {
        if (self.event_type) |event| {
            return std.mem.eql(u8, event, "done") or std.mem.eql(u8, event, "[DONE]");
        }
        return false;
    }
};

/// Stream manager for managing multiple concurrent streams
pub const StreamManager = struct {
    allocator: std.mem.Allocator,
    active_streams: std.ArrayList(*StreamSession),
    max_concurrent_streams: u32,

    pub fn init(allocator: std.mem.Allocator, max_concurrent: u32) StreamManager {
        return .{
            .allocator = allocator,
            .active_streams = .{
                .items = &[_]*StreamSession{},
                .capacity = 0,
            },
            .max_concurrent_streams = max_concurrent,
        };
    }

    pub fn deinit(self: *StreamManager) void {
        // Clean up all active streams
        for (self.active_streams.items) |session| {
            session.deinit();
            self.allocator.destroy(session);
        }
        self.active_streams.deinit(self.allocator);
    }

    /// Create a new stream session
    pub fn createStream(
        self: *StreamManager,
        provider: types.Provider,
        callback: types.StreamCallback,
        user_data: ?*anyopaque,
    ) !*StreamSession {
        if (self.active_streams.items.len >= self.max_concurrent_streams) {
            return error.TooManyStreams;
        }

        const session = try self.allocator.create(StreamSession);
        session.* = StreamSession.init(self.allocator, provider, callback, user_data);

        try self.active_streams.append(session);

        return session;
    }

    /// Remove a completed stream
    pub fn removeStream(self: *StreamManager, session: *StreamSession) void {
        for (self.active_streams.items, 0..) |stream, i| {
            if (stream == session) {
                _ = self.active_streams.swapRemove(i);
                session.deinit();
                self.allocator.destroy(session);
                break;
            }
        }
    }

    /// Cancel all active streams
    pub fn cancelAll(self: *StreamManager) void {
        for (self.active_streams.items) |session| {
            session.cancel();
        }
    }

    /// Get count of active streams
    pub fn activeCount(self: *const StreamManager) usize {
        return self.active_streams.items.len;
    }
};

// Tests
test "stream session lifecycle" {
    const TestData = struct {
        chunks_received: u32 = 0,

        fn callback(chunk: []const u8, user_data: ?*anyopaque) void {
            _ = chunk;
            const data: *@This() = @ptrCast(@alignCast(user_data.?));
            data.chunks_received += 1;
        }
    };

    var test_data = TestData{};
    var session = StreamSession.init(
        std.testing.allocator,
        .ollama,
        TestData.callback,
        &test_data,
    );
    defer session.deinit();

    try std.testing.expectEqual(StreamState.idle, session.state);

    // Process chunks
    session.processChunk("Hello");
    session.processChunk(" world");

    try std.testing.expectEqual(StreamState.streaming, session.state);
    try std.testing.expectEqual(@as(u32, 2), test_data.chunks_received);

    // Complete
    const response = session.complete();
    try std.testing.expect(response.success);
    try std.testing.expectEqual(StreamState.completed, session.state);
}

test "SSE parser" {
    var parser = SSEParser.init(std.testing.allocator);
    defer parser.deinit();

    // Parse SSE event
    const sse_data = "data: Hello world\n\n";
    const result = try parser.parseChunk(sse_data);

    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.startsWith(u8, result.?, "Hello world"));
}

test "stream manager" {
    const TestCallback = struct {
        fn callback(chunk: []const u8, user_data: ?*anyopaque) void {
            _ = chunk;
            _ = user_data;
        }
    };

    var manager = StreamManager.init(std.testing.allocator, 10);
    defer manager.deinit();

    // Create stream
    const stream = try manager.createStream(.ollama, TestCallback.callback, null);
    try std.testing.expectEqual(@as(usize, 1), manager.activeCount());

    // Complete and remove
    _ = stream.complete();
    manager.removeStream(stream);
    try std.testing.expectEqual(@as(usize, 0), manager.activeCount());
}

test "stream cancellation" {
    const TestData = struct {
        chunks_received: u32 = 0,

        fn callback(chunk: []const u8, user_data: ?*anyopaque) void {
            _ = chunk;
            const data: *@This() = @ptrCast(@alignCast(user_data.?));
            data.chunks_received += 1;
        }
    };

    var test_data = TestData{};
    var session = StreamSession.init(
        std.testing.allocator,
        .anthropic,
        TestData.callback,
        &test_data,
    );
    defer session.deinit();

    session.processChunk("chunk1");
    try std.testing.expectEqual(@as(u32, 1), test_data.chunks_received);

    // Cancel
    session.cancel();

    // Further chunks should be ignored
    session.processChunk("chunk2");
    try std.testing.expectEqual(@as(u32, 1), test_data.chunks_received); // Still 1
    try std.testing.expectEqual(StreamState.cancelled, session.state);
}

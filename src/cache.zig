//! Request/Response caching with LRU eviction and TTL
//! Saves costs and improves performance for repeated queries

const std = @import("std");
const types = @import("types.zig");

/// Cache entry with TTL
pub const CacheEntry = struct {
    key: []const u8,
    response: types.CompletionResponse,
    created_at: i64,
    ttl_seconds: u32,
    access_count: u32,
    last_accessed: i64,

    /// Check if entry is expired
    pub fn isExpired(self: CacheEntry) bool {
        const now = std.time.timestamp();
        return (now - self.created_at) > self.ttl_seconds;
    }

    /// Get age in seconds
    pub fn getAge(self: CacheEntry) i64 {
        const now = std.time.timestamp();
        return now - self.created_at;
    }

    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        self.response.deinit(allocator);
    }
};

/// LRU Cache with TTL support
pub const ResponseCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    max_size: usize,
    ttl_seconds: u32,

    // Statistics
    hits: u64 = 0,
    misses: u64 = 0,
    evictions: u64 = 0,
    expirations: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, max_size: usize, ttl_seconds: u32) ResponseCache {
        return ResponseCache{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_size = max_size,
            .ttl_seconds = ttl_seconds,
        };
    }

    pub fn deinit(self: *ResponseCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            var cache_entry = entry.value_ptr.*;
            cache_entry.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    /// Get cached response if available and not expired
    pub fn get(self: *ResponseCache, prompt: []const u8) ?types.CompletionResponse {
        const entry_ptr = self.entries.getPtr(prompt) orelse {
            self.misses += 1;
            return null;
        };

        // Check if expired
        if (entry_ptr.isExpired()) {
            var entry = entry_ptr.*;
            entry.deinit(self.allocator);
            _ = self.entries.remove(prompt);
            self.expirations += 1;
            self.misses += 1;
            return null;
        }

        // Update access time and count
        entry_ptr.last_accessed = std.time.timestamp();
        entry_ptr.access_count += 1;
        self.hits += 1;

        // Return copy of response
        return entry_ptr.response.clone(self.allocator) catch {
            self.misses += 1;
            return null;
        };
    }

    /// Put response in cache
    pub fn put(
        self: *ResponseCache,
        prompt: []const u8,
        response: types.CompletionResponse,
    ) !void {
        // Check if we need to evict
        if (self.entries.count() >= self.max_size) {
            try self.evictOldest();
        }

        // Clone the response for storage
        const response_copy = try response.clone(self.allocator);
        errdefer response_copy.deinit(self.allocator);

        const entry = CacheEntry{
            .key = try self.allocator.dupe(u8, prompt),
            .response = response_copy,
            .created_at = std.time.timestamp(),
            .ttl_seconds = self.ttl_seconds,
            .access_count = 0,
            .last_accessed = std.time.timestamp(),
        };

        try self.entries.put(entry.key, entry);
    }

    /// Evict the least recently used entry
    fn evictOldest(self: *ResponseCache) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_access: i64 = std.math.maxInt(i64);

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.last_accessed < oldest_access) {
                oldest_access = entry.value_ptr.last_accessed;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.entries.getPtr(key)) |entry_ptr| {
                var entry = entry_ptr.*;
                entry.deinit(self.allocator);
                _ = self.entries.remove(key);
                self.evictions += 1;
            }
        }
    }

    /// Clear all expired entries
    pub fn clearExpired(self: *ResponseCache) void {
        var keys_to_remove: std.ArrayList([]const u8) = .empty;
        defer keys_to_remove.deinit(self.allocator);

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.isExpired()) {
                keys_to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (keys_to_remove.items) |key| {
            if (self.entries.getPtr(key)) |entry_ptr| {
                var entry = entry_ptr.*;
                entry.deinit(self.allocator);
                _ = self.entries.remove(key);
                self.expirations += 1;
            }
        }
    }

    /// Clear all cache entries
    pub fn clear(self: *ResponseCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            var cache_entry = entry.value_ptr.*;
            cache_entry.deinit(self.allocator);
        }
        self.entries.clearAndFree();
        self.hits = 0;
        self.misses = 0;
        self.evictions = 0;
        self.expirations = 0;
    }

    /// Get cache statistics
    pub fn getStats(self: ResponseCache) CacheStats {
        const total_requests = self.hits + self.misses;
        const hit_rate = if (total_requests > 0)
            @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total_requests))
        else
            0.0;

        return CacheStats{
            .entries = self.entries.count(),
            .max_size = self.max_size,
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
            .evictions = self.evictions,
            .expirations = self.expirations,
        };
    }

    /// Generate cache key from request
    pub fn generateKey(
        allocator: std.mem.Allocator,
        request: types.CompletionRequest,
    ) ![]const u8 {
        // Hash prompt + provider + temperature + max_tokens
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(request.prompt);

        if (request.provider) |provider| {
            hasher.update(provider.toString());
        }

        if (request.temperature) |temp| {
            const temp_bytes = std.mem.asBytes(&temp);
            hasher.update(temp_bytes);
        }

        if (request.max_tokens) |tokens| {
            const tokens_bytes = std.mem.asBytes(&tokens);
            hasher.update(tokens_bytes);
        }

        const hash = hasher.final();
        return try std.fmt.allocPrint(allocator, "{x}", .{hash});
    }
};

/// Cache statistics
pub const CacheStats = struct {
    entries: usize,
    max_size: usize,
    hits: u64,
    misses: u64,
    hit_rate: f64,
    evictions: u64,
    expirations: u64,

    pub fn format(
        self: CacheStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            \\Cache Stats:
            \\  Entries: {}/{} ({d:.1}% full)
            \\  Hits: {}
            \\  Misses: {}
            \\  Hit Rate: {d:.1}%
            \\  Evictions: {}
            \\  Expirations: {}
        , .{
            self.entries,
            self.max_size,
            @as(f64, @floatFromInt(self.entries)) / @as(f64, @floatFromInt(self.max_size)) * 100.0,
            self.hits,
            self.misses,
            self.hit_rate * 100.0,
            self.evictions,
            self.expirations,
        });
    }
};

/// Multi-level cache with different TTLs
pub const MultiLevelCache = struct {
    short_term: ResponseCache, // 5 minutes
    medium_term: ResponseCache, // 1 hour
    long_term: ResponseCache, // 24 hours

    pub fn init(allocator: std.mem.Allocator) MultiLevelCache {
        return MultiLevelCache{
            .short_term = ResponseCache.init(allocator, 100, 300), // 100 entries, 5min
            .medium_term = ResponseCache.init(allocator, 500, 3600), // 500 entries, 1hr
            .long_term = ResponseCache.init(allocator, 1000, 86400), // 1000 entries, 24hr
        };
    }

    pub fn deinit(self: *MultiLevelCache) void {
        self.short_term.deinit();
        self.medium_term.deinit();
        self.long_term.deinit();
    }

    pub fn get(self: *MultiLevelCache, prompt: []const u8) ?types.CompletionResponse {
        // Try short term first (fastest)
        if (self.short_term.get(prompt)) |response| {
            return response;
        }

        // Try medium term
        if (self.medium_term.get(prompt)) |response| {
            return response;
        }

        // Try long term
        if (self.long_term.get(prompt)) |response| {
            return response;
        }

        return null;
    }

    pub fn put(
        self: *MultiLevelCache,
        prompt: []const u8,
        response: types.CompletionResponse,
        level: CacheLevel,
    ) !void {
        switch (level) {
            .short => try self.short_term.put(prompt, response),
            .medium => try self.medium_term.put(prompt, response),
            .long => try self.long_term.put(prompt, response),
        }
    }

    pub fn clear(self: *MultiLevelCache) void {
        self.short_term.clear();
        self.medium_term.clear();
        self.long_term.clear();
    }
};

pub const CacheLevel = enum {
    short,
    medium,
    long,
};

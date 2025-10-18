//! Omen client for intelligent AI routing
//! Implements real HTTP API calls to Omen server
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("../types.zig");

pub const OmenClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    client: zhttp.Client,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !OmenClient {
        return OmenClient{
            .allocator = allocator,
            .endpoint = endpoint,
            .client = zhttp.Client.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *OmenClient) void {
        self.client.deinit();
    }

    /// Complete a prompt using Omen's intelligent routing
    pub fn complete(self: *OmenClient, request: types.CompletionRequest) !types.CompletionResponse {
        const start_time = std.time.milliTimestamp();

        // Build Omen API URL: http://localhost:3000/v1/chat/completions
        const api_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1/chat/completions",
            .{self.endpoint},
        );
        defer self.allocator.free(api_url);

        // Build system prompt
        const system_content = request.system_prompt orelse "You are a helpful coding assistant.";

        // Create JSON request body (OpenAI-compatible format)
        // {
        //   "messages": [
        //     {"role": "system", "content": "..."},
        //     {"role": "user", "content": "..."}
        //   ],
        //   "max_tokens": 100,
        //   "temperature": 0.7
        // }
        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"messages":[{{"role":"system","content":"{s}"}},{{"role":"user","content":"{s}"}}],"max_tokens":{},"temperature":{}}}
        ,
            .{
                system_content,
                request.prompt,
                request.max_tokens orelse 100,
                request.temperature orelse 0.7,
            },
        );
        defer self.allocator.free(request_body);

        // Build HTTP POST request
        var http_request = zhttp.Request.init(self.allocator, .POST, api_url);
        defer http_request.deinit();
        http_request.setBody(zhttp.Body.fromString(request_body));
        try http_request.addHeader("Content-Type", "application/json");

        // Make HTTP POST request
        var response = self.client.send(http_request) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .omen,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Omen HTTP error: {s}",
                    .{@errorName(err)},
                ),
            };
        };
        defer response.deinit();

        // Parse JSON response
        // {
        //   "id": "chatcmpl-...",
        //   "object": "chat.completion",
        //   "choices": [{
        //     "message": {"role": "assistant", "content": "the actual completion"},
        //     "finish_reason": "stop"
        //   }],
        //   "usage": {...},
        //   "provider": "anthropic"  // Omen-specific metadata
        // }

        // Read response body
        const response_body = response.readAll(1024 * 1024) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .omen,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to read response: {s}",
                    .{@errorName(err)},
                ),
            };
        };
        defer self.allocator.free(response_body);

        // Extract completion text from nested JSON structure
        const completion_text = try self.extractCompletionFromResponse(response_body);
        defer if (completion_text) |text| self.allocator.free(text);

        // Extract actual provider that handled the request (if available)
        const actual_provider = try self.extractJsonField(response_body, "provider");
        defer if (actual_provider) |text| self.allocator.free(text);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        if (completion_text) |text| {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, text),
                .provider = .omen,
                .confidence = 0.9, // Omen's routing is high quality
                .latency_ms = latency,
                .success = true,
                .error_message = null,
            };
        } else {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .omen,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Failed to parse Omen response"),
            };
        }
    }

    /// Get Omen routing statistics
    pub fn getStats(self: *OmenClient) !OmenStats {
        const api_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/stats",
            .{self.endpoint},
        );
        defer self.allocator.free(api_url);

        var http_request = zhttp.Request.init(self.allocator, .GET, api_url);
        defer http_request.deinit();

        var response = self.client.send(http_request) catch {
            return OmenStats{
                .total_requests = 0,
                .avg_latency_ms = 0,
                .providers_used = &.{},
            };
        };
        defer response.deinit();

        // TODO: Parse JSON stats response
        return OmenStats{
            .total_requests = 0,
            .avg_latency_ms = 0,
            .providers_used = &.{},
        };
    }

    /// Check if Omen is responsive
    pub fn ping(self: *OmenClient) !bool {
        const api_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/health",
            .{self.endpoint},
        );
        defer self.allocator.free(api_url);

        var http_request = zhttp.Request.init(self.allocator, .GET, api_url);
        defer http_request.deinit();

        var response = self.client.send(http_request) catch {
            return false;
        };
        defer response.deinit();

        return response.status == 200;
    }

    /// Parse OpenAI-format JSON response using std.json
    const OmenMessage = struct {
        role: []const u8,
        content: []const u8,
    };

    const OmenChoice = struct {
        index: ?i32 = null,
        message: OmenMessage,
        finish_reason: ?[]const u8 = null,
    };

    const OmenUsage = struct {
        prompt_tokens: ?i32 = null,
        completion_tokens: ?i32 = null,
        total_tokens: ?i32 = null,
    };

    const OmenResponse = struct {
        id: ?[]const u8 = null,
        object: ?[]const u8 = null,
        created: ?i64 = null,
        choices: []OmenChoice,
        usage: ?OmenUsage = null,
        provider: ?[]const u8 = null,
    };

    fn extractCompletionFromResponse(self: *OmenClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            OmenResponse,
            self.allocator,
            json_text,
            .{},
        ) catch |err| {
            std.debug.print("[OmenClient] JSON parse error: {s}\n", .{@errorName(err)});
            return null;
        };
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return null;

        return try self.allocator.dupe(u8, parsed.value.choices[0].message.content);
    }

    fn extractJsonField(self: *OmenClient, json_text: []const u8, field: []const u8) !?[]const u8 {
        // Simple fallback for provider field extraction
        const pattern = try std.fmt.allocPrint(self.allocator, "\"{s}\":\"", .{field});
        defer self.allocator.free(pattern);

        const start_idx = std.mem.indexOf(u8, json_text, pattern) orelse return null;
        const value_start = start_idx + pattern.len;

        const remaining = json_text[value_start..];
        const end_idx = std.mem.indexOf(u8, remaining, "\"") orelse return null;

        return try self.allocator.dupe(u8, remaining[0..end_idx]);
    }
};

pub const OmenStats = struct {
    total_requests: u64,
    avg_latency_ms: u32,
    providers_used: []const []const u8,
};

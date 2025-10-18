//! Anthropic Claude client for direct API access
//! Implements real HTTP API calls to Anthropic's Claude API
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("../types.zig");

pub const AnthropicClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,
    client: zhttp.Client,

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: ?[]const u8, endpoint: ?[]const u8) !AnthropicClient {
        return AnthropicClient{
            .allocator = allocator,
            .api_key = api_key,
            .model = model orelse "claude-sonnet-4-20250514",
            .endpoint = endpoint orelse "https://api.anthropic.com/v1/messages",
            .client = zhttp.Client.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *AnthropicClient) void {
        self.client.deinit();
    }

    /// Complete a prompt using Anthropic Claude
    pub fn complete(self: *AnthropicClient, request: types.CompletionRequest) !types.CompletionResponse {
        const start_time = std.time.milliTimestamp();

        // Build request body for Anthropic Messages API
        // {
        //   "model": "claude-sonnet-4-20250514",
        //   "max_tokens": 1024,
        //   "messages": [
        //     {"role": "user", "content": "Hello, Claude"}
        //   ]
        // }
        const system_prompt = request.system_prompt orelse "You are a helpful coding assistant.";

        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"model":"{s}","max_tokens":{},"system":"{s}","messages":[{{"role":"user","content":"{s}"}}]}}
        ,
            .{
                self.model,
                request.max_tokens orelse 1024,
                system_prompt,
                request.prompt,
            },
        );
        defer self.allocator.free(request_body);

        // Build HTTP POST request
        var http_request = zhttp.Request.init(self.allocator, .POST, self.endpoint);
        defer http_request.deinit();
        http_request.setBody(zhttp.Body.fromString(request_body));

        // Anthropic-specific headers
        try http_request.addHeader("Content-Type", "application/json");
        try http_request.addHeader("x-api-key", self.api_key);
        try http_request.addHeader("anthropic-version", "2023-06-01");

        // Make HTTP POST request
        var response = self.client.send(http_request) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .anthropic,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Anthropic HTTP error: {s}",
                    .{@errorName(err)},
                ),
            };
        };
        defer response.deinit();

        // Read response body
        const response_body = response.readAll(1024 * 1024) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .anthropic,
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

        // Parse JSON response
        // {
        //   "id": "msg_...",
        //   "type": "message",
        //   "role": "assistant",
        //   "content": [
        //     {"type": "text", "text": "Hello! How can I help you today?"}
        //   ],
        //   "model": "claude-sonnet-4-20250514",
        //   "stop_reason": "end_turn",
        //   "usage": {...}
        // }

        // Extract text from content array
        const completion_text = try self.extractTextFromContent(response_body);
        defer if (completion_text) |text| self.allocator.free(text);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        if (completion_text) |text| {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, text),
                .provider = .anthropic,
                .confidence = 0.95, // Claude is high quality
                .latency_ms = latency,
                .success = true,
                .error_message = null,
            };
        } else {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .anthropic,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Failed to parse Anthropic response"),
            };
        }
    }

    /// Check if Anthropic API is accessible
    pub fn ping(self: *AnthropicClient) !bool {
        // Anthropic doesn't have a dedicated health endpoint
        // We can check if the API key is valid by making a minimal request
        const test_request = types.CompletionRequest{
            .prompt = "Hi",
            .max_tokens = 1,
        };

        const response = self.complete(test_request) catch return false;
        defer response.deinit(self.allocator);

        return response.success;
    }

    /// Parse Anthropic JSON response using std.json
    const AnthropicContent = struct {
        type: []const u8,
        text: []const u8,
    };

    const AnthropicUsage = struct {
        input_tokens: ?i32 = null,
        output_tokens: ?i32 = null,
    };

    const AnthropicResponse = struct {
        id: ?[]const u8 = null,
        type: ?[]const u8 = null,
        role: ?[]const u8 = null,
        content: []AnthropicContent,
        model: ?[]const u8 = null,
        stop_reason: ?[]const u8 = null,
        usage: ?AnthropicUsage = null,
    };

    fn extractTextFromContent(self: *AnthropicClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            AnthropicResponse,
            self.allocator,
            json_text,
            .{},
        ) catch |err| {
            std.debug.print("[AnthropicClient] JSON parse error: {s}\n", .{@errorName(err)});
            return null;
        };
        defer parsed.deinit();

        if (parsed.value.content.len == 0) return null;

        // Find first text content block
        for (parsed.value.content) |content_block| {
            if (std.mem.eql(u8, content_block.type, "text")) {
                return try self.allocator.dupe(u8, content_block.text);
            }
        }

        return null;
    }
};

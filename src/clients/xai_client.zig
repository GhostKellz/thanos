//! xAI Grok client for direct API access
//! Implements real HTTP API calls to xAI's Grok API (OpenAI-compatible)
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("../types.zig");

pub const XAIClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,
    client: zhttp.Client,

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: ?[]const u8, endpoint: ?[]const u8) !XAIClient {
        return XAIClient{
            .allocator = allocator,
            .api_key = api_key,
            .model = model orelse "grok-beta",
            .endpoint = endpoint orelse "https://api.x.ai/v1/chat/completions",
            .client = zhttp.Client.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *XAIClient) void {
        self.client.deinit();
    }

    /// Complete a prompt using xAI Grok
    pub fn complete(self: *XAIClient, request: types.CompletionRequest) !types.CompletionResponse {
        const start_time = std.time.milliTimestamp();

        // xAI uses OpenAI-compatible API format
        // {
        //   "model": "grok-beta",
        //   "messages": [
        //     {"role": "system", "content": "You are Grok, a chatbot inspired by the Hitchhiker's Guide to the Galaxy."},
        //     {"role": "user", "content": "What is the meaning of life?"}
        //   ],
        //   "max_tokens": 1024,
        //   "temperature": 0.7
        // }
        const system_content = request.system_prompt orelse "You are Grok, a helpful and witty AI assistant.";

        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"model":"{s}","messages":[{{"role":"system","content":"{s}"}},{{"role":"user","content":"{s}"}}],"max_tokens":{},"temperature":{}}}
        ,
            .{
                self.model,
                system_content,
                request.prompt,
                request.max_tokens orelse 1024,
                request.temperature orelse 0.7,
            },
        );
        defer self.allocator.free(request_body);

        // Build HTTP POST request
        var http_request = zhttp.Request.init(self.allocator, .POST, self.endpoint);
        defer http_request.deinit();
        http_request.setBody(zhttp.Body.fromString(request_body));

        // xAI uses Bearer token auth like OpenAI
        try http_request.addHeader("Content-Type", "application/json");
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try http_request.addHeader("Authorization", auth_header);

        // Make HTTP POST request
        var response = self.client.send(http_request) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .xai,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "xAI HTTP error: {s}",
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
                .provider = .xai,
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

        // Parse JSON response (OpenAI-compatible format)
        const completion_text = try self.extractCompletionFromResponse(response_body);
        defer if (completion_text) |text| self.allocator.free(text);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        if (completion_text) |text| {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, text),
                .provider = .xai,
                .confidence = 0.85,
                .latency_ms = latency,
                .success = true,
                .error_message = null,
            };
        } else {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .xai,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Failed to parse xAI response"),
            };
        }
    }

    /// Check if xAI API is accessible
    pub fn ping(self: *XAIClient) !bool {
        // Make a minimal request to test connectivity
        const test_request = types.CompletionRequest{
            .prompt = "Hi",
            .max_tokens = 1,
        };

        const response = self.complete(test_request) catch return false;
        defer response.deinit(self.allocator);

        return response.success;
    }

    /// Parse xAI JSON response using std.json (OpenAI-compatible)
    const XAIMessage = struct {
        role: []const u8,
        content: []const u8,
    };

    const XAIChoice = struct {
        index: ?i32 = null,
        message: XAIMessage,
        finish_reason: ?[]const u8 = null,
    };

    const XAIUsage = struct {
        prompt_tokens: ?i32 = null,
        completion_tokens: ?i32 = null,
        total_tokens: ?i32 = null,
    };

    const XAIResponse = struct {
        id: ?[]const u8 = null,
        object: ?[]const u8 = null,
        created: ?i64 = null,
        model: ?[]const u8 = null,
        choices: []XAIChoice,
        usage: ?XAIUsage = null,
    };

    fn extractCompletionFromResponse(self: *XAIClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            XAIResponse,
            self.allocator,
            json_text,
            .{},
        ) catch |err| {
            std.debug.print("[XAIClient] JSON parse error: {s}\n", .{@errorName(err)});
            return null;
        };
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return null;

        return try self.allocator.dupe(u8, parsed.value.choices[0].message.content);
    }
};

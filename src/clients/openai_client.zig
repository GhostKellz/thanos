//! OpenAI GPT client for direct API access
//! Implements real HTTP API calls to OpenAI's Chat Completions API
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("../types.zig");

pub const OpenAIClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,
    client: zhttp.Client,

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: ?[]const u8, endpoint: ?[]const u8) !OpenAIClient {
        return OpenAIClient{
            .allocator = allocator,
            .api_key = api_key,
            .model = model orelse "gpt-4-turbo-preview",
            .endpoint = endpoint orelse "https://api.openai.com/v1/chat/completions",
            .client = zhttp.Client.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *OpenAIClient) void {
        self.client.deinit();
    }

    /// Complete a prompt using OpenAI GPT
    pub fn complete(self: *OpenAIClient, request: types.CompletionRequest) !types.CompletionResponse {
        const start_time = std.time.milliTimestamp();

        // Build request body for OpenAI Chat Completions API
        // {
        //   "model": "gpt-4-turbo-preview",
        //   "messages": [
        //     {"role": "system", "content": "You are a helpful assistant."},
        //     {"role": "user", "content": "Hello!"}
        //   ],
        //   "max_tokens": 1024,
        //   "temperature": 0.7
        // }
        const system_content = request.system_prompt orelse "You are a helpful coding assistant.";

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

        // OpenAI-specific headers
        try http_request.addHeader("Content-Type", "application/json");
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try http_request.addHeader("Authorization", auth_header);

        // Make HTTP POST request
        var response = self.client.send(http_request) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .openai,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "OpenAI HTTP error: {s}",
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
                .provider = .openai,
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

        // Parse JSON response (OpenAI format, same as Omen)
        // {
        //   "id": "chatcmpl-...",
        //   "object": "chat.completion",
        //   "choices": [{
        //     "message": {"role": "assistant", "content": "Hello! How can I help?"},
        //     "finish_reason": "stop"
        //   }],
        //   "usage": {...}
        // }

        const completion_text = try self.extractCompletionFromResponse(response_body);
        defer if (completion_text) |text| self.allocator.free(text);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        if (completion_text) |text| {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, text),
                .provider = .openai,
                .confidence = 0.9,
                .latency_ms = latency,
                .success = true,
                .error_message = null,
            };
        } else {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .openai,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Failed to parse OpenAI response"),
            };
        }
    }

    /// List available models
    pub fn listModels(self: *OpenAIClient) ![][]const u8 {
        const models_endpoint = "https://api.openai.com/v1/models";

        var http_request = zhttp.Request.init(self.allocator, .GET, models_endpoint);
        defer http_request.deinit();

        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try http_request.addHeader("Authorization", auth_header);

        var response = self.client.send(http_request) catch {
            return &.{};
        };
        defer response.deinit();

        // TODO: Parse JSON and extract model IDs
        return &.{};
    }

    /// Check if OpenAI API is accessible
    pub fn ping(self: *OpenAIClient) !bool {
        const models_endpoint = "https://api.openai.com/v1/models";

        var http_request = zhttp.Request.init(self.allocator, .GET, models_endpoint);
        defer http_request.deinit();

        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try http_request.addHeader("Authorization", auth_header);

        var response = self.client.send(http_request) catch {
            return false;
        };
        defer response.deinit();

        return response.status == 200;
    }

    /// Parse OpenAI JSON response using std.json
    const OpenAIMessage = struct {
        role: []const u8,
        content: []const u8,
    };

    const OpenAIChoice = struct {
        index: ?i32 = null,
        message: OpenAIMessage,
        finish_reason: ?[]const u8 = null,
    };

    const OpenAIUsage = struct {
        prompt_tokens: ?i32 = null,
        completion_tokens: ?i32 = null,
        total_tokens: ?i32 = null,
    };

    const OpenAIResponse = struct {
        id: ?[]const u8 = null,
        object: ?[]const u8 = null,
        created: ?i64 = null,
        model: ?[]const u8 = null,
        choices: []OpenAIChoice,
        usage: ?OpenAIUsage = null,
    };

    fn extractCompletionFromResponse(self: *OpenAIClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            OpenAIResponse,
            self.allocator,
            json_text,
            .{},
        ) catch |err| {
            std.debug.print("[OpenAIClient] JSON parse error: {s}\n", .{@errorName(err)});
            return null;
        };
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return null;

        return try self.allocator.dupe(u8, parsed.value.choices[0].message.content);
    }
};

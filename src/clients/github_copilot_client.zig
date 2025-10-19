// GitHub Copilot client for native code completions
//! Implements GitHub Copilot API integration via gh auth token
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("../types.zig");

pub const GitHubCopilotClient = struct {
    allocator: std.mem.Allocator,
    api_token: []const u8,
    endpoint: []const u8,
    client: zhttp.Client,

    /// Initialize GitHub Copilot client
    /// Uses gh CLI auth token or provided API token
    pub fn init(allocator: std.mem.Allocator, api_token: ?[]const u8, endpoint: ?[]const u8) !GitHubCopilotClient {
        // If no token provided, try to get from gh CLI
        const token = if (api_token) |t|
            try allocator.dupe(u8, t)
        else
            try getGHToken(allocator);

        return GitHubCopilotClient{
            .allocator = allocator,
            .api_token = token,
            .endpoint = endpoint orelse "https://api.githubcopilot.com/v1/completions",
            .client = zhttp.Client.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *GitHubCopilotClient) void {
        self.allocator.free(self.api_token);
        self.client.deinit();
    }

    /// Get GitHub token from gh CLI
    fn getGHToken(allocator: std.mem.Allocator) ![]const u8 {
        // Try to execute: gh auth token
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "gh", "auth", "token" },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.GhAuthFailed;
        }

        // Trim whitespace
        const trimmed = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
        return try allocator.dupe(u8, trimmed);
    }

    /// Complete code using GitHub Copilot
    pub fn complete(self: *GitHubCopilotClient, request: types.CompletionRequest) !types.CompletionResponse {
        const start_time = std.time.milliTimestamp();

        // GitHub Copilot API request format
        // {
        //   "prompt": "code context",
        //   "suffix": "code after cursor",
        //   "max_tokens": 100,
        //   "temperature": 0.0,
        //   "language": "zig"
        // }

        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"prompt":"{s}","suffix":"","max_tokens":{},"temperature":{},"language":"{s}"}}
        ,
            .{
                request.prompt,
                request.max_tokens orelse 100,
                request.temperature orelse 0.2,
                request.language orelse "plaintext",
            },
        );
        defer self.allocator.free(request_body);

        // Build HTTP POST request
        var http_request = zhttp.Request.init(self.allocator, .POST, self.endpoint);
        defer http_request.deinit();
        http_request.setBody(zhttp.Body.fromString(request_body));

        try http_request.addHeader("Content-Type", "application/json");
        try http_request.addHeader("Authorization", try std.fmt.allocPrint(
            self.allocator,
            "Bearer {s}",
            .{self.api_token},
        ));
        try http_request.addHeader("Editor-Version", "Grim/0.1.0");
        try http_request.addHeader("Editor-Plugin-Version", "Thanos/0.2.0");

        // Make HTTP POST request
        var response = self.client.send(http_request) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .github_copilot,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "GitHub Copilot HTTP error: {s}",
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
                .provider = .github_copilot,
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
        //   "choices": [
        //     {
        //       "text": "completion text",
        //       "index": 0,
        //       "finish_reason": "stop"
        //     }
        //   ]
        // }

        const completion_text = try self.parseCompletionResponse(response_body);
        defer if (completion_text) |text| self.allocator.free(text);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        if (completion_text) |text| {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, text),
                .provider = .github_copilot,
                .confidence = 0.9, // Copilot is high quality
                .latency_ms = latency,
                .success = true,
                .error_message = null,
            };
        } else {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .github_copilot,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Failed to parse GitHub Copilot response"),
            };
        }
    }

    /// Check if GitHub Copilot is accessible
    pub fn ping(self: *GitHubCopilotClient) !bool {
        // Simple ping with minimal request
        const test_request = types.CompletionRequest{
            .prompt = "//",
            .max_tokens = 1,
            .language = "javascript",
        };

        const response = self.complete(test_request) catch return false;
        defer response.deinit(self.allocator);

        return response.success;
    }

    const CopilotChoice = struct {
        text: []const u8,
        index: ?i32 = null,
        finish_reason: ?[]const u8 = null,
    };

    const CopilotResponse = struct {
        choices: []CopilotChoice,
        id: ?[]const u8 = null,
        model: ?[]const u8 = null,
    };

    fn parseCompletionResponse(self: *GitHubCopilotClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            CopilotResponse,
            self.allocator,
            json_text,
            .{},
        ) catch |err| {
            std.debug.print("[GitHubCopilotClient] JSON parse error: {s}\n", .{@errorName(err)});
            return null;
        };
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return null;

        // Return first choice
        return try self.allocator.dupe(u8, parsed.value.choices[0].text);
    }

    /// Complete with streaming (GitHub Copilot supports SSE)
    pub fn completeStreaming(self: *GitHubCopilotClient, request: types.StreamingCompletionRequest) !types.StreamingCompletionResponse {
        const start_time = std.time.milliTimestamp();

        // Request body with stream: true
        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"prompt":"{s}","suffix":"","max_tokens":{},"temperature":{},"language":"{s}","stream":true}}
        ,
            .{
                request.prompt,
                request.max_tokens orelse 100,
                request.temperature orelse 0.2,
                request.language orelse "plaintext",
            },
        );
        defer self.allocator.free(request_body);

        var http_request = zhttp.Request.init(self.allocator, .POST, self.endpoint);
        defer http_request.deinit();
        http_request.setBody(zhttp.Body.fromString(request_body));

        try http_request.addHeader("Content-Type", "application/json");
        try http_request.addHeader("Authorization", try std.fmt.allocPrint(
            self.allocator,
            "Bearer {s}",
            .{self.api_token},
        ));

        var response = self.client.send(http_request) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.StreamingCompletionResponse{
                .provider = .github_copilot,
                .total_tokens = 0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "GitHub Copilot HTTP error: {s}",
                    .{@errorName(err)},
                ),
            };
        };
        defer response.deinit();

        // Read SSE stream
        var total_tokens: u32 = 0;
        var buffer: [8192]u8 = undefined;

        while (true) {
            const line = response.readLine(&buffer) catch |err| {
                if (err == error.EndOfStream) break;
                const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
                return types.StreamingCompletionResponse{
                    .provider = .github_copilot,
                    .total_tokens = total_tokens,
                    .latency_ms = latency,
                    .success = false,
                    .error_message = try std.fmt.allocPrint(
                        self.allocator,
                        "Stream read error: {s}",
                        .{@errorName(err)},
                    ),
                };
            };

            if (line.len == 0 or !std.mem.startsWith(u8, line, "data: ")) continue;

            const json_data = line["data: ".len..];
            if (std.mem.eql(u8, json_data, "[DONE]")) break;

            // Parse chunk and call callback
            const text = try self.parseStreamingChunk(json_data);
            defer if (text) |t| self.allocator.free(t);

            if (text) |t| {
                request.callback(t, request.user_data);
                total_tokens += @intCast(t.len / 4);
            }
        }

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        return types.StreamingCompletionResponse{
            .provider = .github_copilot,
            .total_tokens = total_tokens,
            .latency_ms = latency,
            .success = true,
            .error_message = null,
        };
    }

    fn parseStreamingChunk(self: *GitHubCopilotClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            CopilotResponse,
            self.allocator,
            json_text,
            .{},
        ) catch return null;
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return null;
        return try self.allocator.dupe(u8, parsed.value.choices[0].text);
    }
};

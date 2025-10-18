//! Ollama client for local AI model inference
//! Implements real HTTP API calls to Ollama server
const std = @import("std");
const zhttp = @import("zhttp");
const types = @import("../types.zig");

pub const OllamaClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    model: []const u8,
    client: zhttp.Client,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8, model: ?[]const u8) !OllamaClient {
        return OllamaClient{
            .allocator = allocator,
            .endpoint = endpoint,
            .model = model orelse "codellama:latest",
            .client = zhttp.Client.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *OllamaClient) void {
        self.client.deinit();
    }

    /// Complete a prompt using Ollama
    pub fn complete(self: *OllamaClient, request: types.CompletionRequest) !types.CompletionResponse {
        const start_time = std.time.milliTimestamp();

        // Build Ollama API request
        const api_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/generate",
            .{self.endpoint},
        );
        defer self.allocator.free(api_url);

        // Create JSON request body
        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"model":"{s}","prompt":"{s}","stream":false,"options":{{"num_predict":{}}}}}
        ,
            .{
                self.model,
                request.prompt,
                request.max_tokens orelse 100,
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
                .provider = .ollama,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Ollama HTTP error: {s}",
                    .{@errorName(err)},
                ),
            };
        };
        defer response.deinit();

        // Parse JSON response
        // {
        //   "model": "codellama",
        //   "created_at": "...",
        //   "response": "the actual completion text",
        //   "done": true
        // }

        // Read response body
        const response_body = response.readAll(1024 * 1024) catch |err| {
            const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .ollama,
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

        // Parse JSON response using std.json
        const completion_text = try self.parseOllamaResponse(response_body);
        defer if (completion_text) |text| self.allocator.free(text);

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start_time));

        if (completion_text) |text| {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, text),
                .provider = .ollama,
                .confidence = 0.8,
                .latency_ms = latency,
                .success = true,
                .error_message = null,
            };
        } else {
            return types.CompletionResponse{
                .text = try self.allocator.dupe(u8, ""),
                .provider = .ollama,
                .confidence = 0.0,
                .latency_ms = latency,
                .success = false,
                .error_message = try self.allocator.dupe(u8, "Failed to parse Ollama response"),
            };
        }
    }

    /// List available models
    pub fn listModels(self: *OllamaClient) ![][]const u8 {
        const api_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/api/tags",
            .{self.endpoint},
        );
        defer self.allocator.free(api_url);

        var http_request = zhttp.Request.init(self.allocator, .GET, api_url);
        defer http_request.deinit();

        var response = self.client.send(http_request) catch {
            return &.{};
        };
        defer response.deinit();

        // TODO: Parse JSON and extract model names
        return &.{};
    }

    /// Check if Ollama is responsive
    pub fn ping(self: *OllamaClient) !bool {
        var http_request = zhttp.Request.init(self.allocator, .GET, self.endpoint);
        defer http_request.deinit();

        var response = self.client.send(http_request) catch {
            return false;
        };
        defer response.deinit();

        return response.status == 200;
    }

    /// Parse Ollama JSON response using std.json
    const OllamaResponse = struct {
        model: []const u8,
        response: []const u8,
        done: bool,
        total_duration: ?i64 = null,
        load_duration: ?i64 = null,
        prompt_eval_count: ?i64 = null,
        eval_count: ?i64 = null,
    };

    fn parseOllamaResponse(self: *OllamaClient, json_text: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            OllamaResponse,
            self.allocator,
            json_text,
            .{},
        ) catch |err| {
            std.debug.print("[OllamaClient] JSON parse error: {s}\n", .{@errorName(err)});
            return null;
        };
        defer parsed.deinit();

        return try self.allocator.dupe(u8, parsed.value.response);
    }
};

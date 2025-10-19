//! Configuration file loading module
//! Loads thanos.toml configuration with TOML parser and environment variable expansion

const std = @import("std");
const zontom = @import("zontom");
const types = @import("types.zig");

/// Load configuration from TOML file
pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !types.Config {
    // Read TOML file
    const file_content = std.fs.cwd().readFileAlloc(path, allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
        std.debug.print("[Config] Failed to read config file {s}: {s}\n", .{ path, @errorName(err) });
        return error.ConfigFileNotFound;
    };
    defer allocator.free(file_content);

    // Parse TOML
    var toml = zontom.parse(allocator, file_content) catch |err| {
        std.debug.print("[Config] Failed to parse TOML: {s}\n", .{@errorName(err)});
        return error.InvalidConfigFormat;
    };
    defer toml.deinit();

    // Initialize config with defaults
    var config = types.Config{};

    // Parse [ai] section for hybrid configuration
    if (zontom.getTable(&toml, "ai")) |ai| {
        if (zontom.getString(ai, "mode")) |mode_str| {
            if (types.ConfigMode.fromString(mode_str)) |mode| {
                config.mode = mode;
            }
        }

        if (zontom.getString(ai, "primary_provider")) |pref_str| {
            if (types.Provider.fromString(pref_str)) |provider| {
                config.preferred_provider = provider;
            }
        }
    }

    // Parse general section (legacy support)
    if (zontom.getTable(&toml, "general")) |general| {
        if (zontom.getBool(general, "debug")) |debug| {
            config.debug = debug;
        }

        if (zontom.getString(general, "preferred_provider")) |pref_str| {
            if (types.Provider.fromString(pref_str)) |provider| {
                config.preferred_provider = provider;
            }
        }

        if (zontom.getInt(general, "request_timeout_ms")) |timeout| {
            config.request_timeout_ms = @intCast(timeout);
        }
    }

    // Parse provider configurations
    if (zontom.getTable(&toml, "providers")) |providers| {
        // Anthropic
        if (zontom.getTable(providers, "anthropic")) |anthropic| {
            config.anthropic = try parseProviderConfig(allocator, anthropic);
        }

        // OpenAI
        if (zontom.getTable(providers, "openai")) |openai| {
            config.openai = try parseProviderConfig(allocator, openai);
        }

        // xAI
        if (zontom.getTable(providers, "xai")) |xai| {
            config.xai = try parseProviderConfig(allocator, xai);
        }

        // Ollama
        if (zontom.getTable(providers, "ollama")) |ollama| {
            config.ollama_config = try parseProviderConfig(allocator, ollama);
        }

        // GitHub Copilot
        if (zontom.getTable(providers, "github_copilot")) |copilot| {
            config.github_copilot = try parseProviderConfig(allocator, copilot);
        }

        // Google
        if (zontom.getTable(providers, "google")) |google| {
            config.google = try parseProviderConfig(allocator, google);
        }
    }

    // Parse routing section
    if (zontom.getTable(&toml, "routing")) |routing| {
        if (zontom.getArray(routing, "fallback_chain")) |chain| {
            var fallback_list: std.ArrayList(types.Provider) = .empty;

            for (chain.items.items) |item| {
                if (item == .string) {
                    if (types.Provider.fromString(item.string)) |provider| {
                        try fallback_list.append(allocator, provider);
                    }
                }
            }

            if (fallback_list.items.len > 0) {
                config.fallback_providers = try allocator.dupe(types.Provider, fallback_list.items);
            }
            fallback_list.deinit(allocator);
        }
    }

    // Parse discovery section
    if (zontom.getTable(&toml, "discovery")) |discovery| {
        if (zontom.getString(discovery, "omen_endpoint")) |endpoint| {
            const expanded = try expandEnvVars(allocator, endpoint);
            config.omen_endpoint = expanded;
        }

        if (zontom.getString(discovery, "ollama_endpoint")) |endpoint| {
            const expanded = try expandEnvVars(allocator, endpoint);
            config.ollama_endpoint = expanded;
        }

        if (zontom.getString(discovery, "bolt_grpc_endpoint")) |endpoint| {
            const expanded = try expandEnvVars(allocator, endpoint);
            config.bolt_grpc_endpoint = expanded;
        }
    }

    // Initialize task routing based on mode
    try config.initTaskRouting(allocator);

    return config;
}

/// Parse a provider configuration section
fn parseProviderConfig(allocator: std.mem.Allocator, provider_table: *const zontom.Table) !types.ProviderConfig {
    var provider_config = types.ProviderConfig{};

    if (zontom.getBool(provider_table, "enabled")) |enabled| {
        provider_config.enabled = enabled;
    }

    if (zontom.getString(provider_table, "api_key")) |api_key| {
        // Expand environment variables
        const expanded = try expandEnvVars(allocator, api_key);
        provider_config.api_key = expanded;
    }

    if (zontom.getString(provider_table, "model")) |model| {
        provider_config.model = try allocator.dupe(u8, model);
    }

    if (zontom.getString(provider_table, "endpoint")) |endpoint| {
        const expanded = try expandEnvVars(allocator, endpoint);
        provider_config.endpoint = expanded;
    }

    if (zontom.getInt(provider_table, "max_tokens")) |max_tokens| {
        provider_config.max_tokens = @intCast(max_tokens);
    }

    if (zontom.getFloat(provider_table, "temperature")) |temperature| {
        provider_config.temperature = @floatCast(temperature);
    }

    return provider_config;
}

/// Expand environment variables in string (e.g., "${VAR}" -> actual value)
pub fn expandEnvVars(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    // Check if value contains environment variable syntax
    if (std.mem.indexOf(u8, value, "${")) |start| {
        if (std.mem.indexOf(u8, value[start..], "}")) |end_offset| {
            const var_name = value[start + 2 .. start + end_offset];

            // Get environment variable
            const env_value = std.process.getEnvVarOwned(allocator, var_name) catch |err| {
                std.debug.print("[Config] Environment variable ${{{s}}} not found: {s}\n", .{ var_name, @errorName(err) });
                return error.EnvVarNotFound;
            };

            // For simple case (entire string is just one env var), return it directly
            if (start == 0 and start + end_offset + 1 == value.len) {
                return env_value;
            }

            // For complex case (env var embedded in string), build new string
            defer allocator.free(env_value);
            const before = value[0..start];
            const after = value[start + end_offset + 1 ..];

            return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ before, env_value, after });
        }
    }

    // No environment variables, return copy of original
    return try allocator.dupe(u8, value);
}

/// Save configuration to TOML file
pub fn saveConfig(allocator: std.mem.Allocator, config: types.Config, path: []const u8) !void {
    _ = allocator;
    _ = config;
    _ = path;
    // TODO: Implement TOML serialization
    return error.NotImplemented;
}

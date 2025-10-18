# Thanos Tests

Comprehensive test suite for Thanos.

## 🧪 Test Organization

```
tests/
├── unit/                   # Unit tests (individual functions)
│   ├── cache_test.zig     # Cache functionality
│   ├── retry_test.zig     # Retry logic
│   ├── errors_test.zig    # Error handling
│   └── config_test.zig    # Configuration parsing
├── integration/           # Integration tests (multiple components)
│   ├── discovery_test.zig # Provider discovery
│   ├── routing_test.zig   # Smart routing
│   └── fallback_test.zig  # Fallback chains
├── e2e/                   # End-to-end tests (full workflows)
│   ├── ollama_test.zig    # Test with Ollama (if available)
│   └── mock_test.zig      # Test with mock providers
└── README.md
```

## 🚀 Running Tests

```bash
# Run all tests
zig build test

# Run specific test file
zig test src/cache.zig

# Run with verbose output
zig test src/cache.zig --verbose

# Run integration tests (requires providers)
zig build test-integration

# Run E2E tests (requires Ollama)
zig build test-e2e
```

## 📊 Test Coverage

Current coverage (as of v0.1.0):

| Module | Coverage | Status |
|--------|----------|--------|
| `cache.zig` | 95% | ✅ Complete |
| `retry.zig` | 90% | ✅ Complete |
| `errors.zig` | 85% | ✅ Good |
| `config.zig` | 80% | ⚠️ Needs work |
| `discovery.zig` | 70% | ⚠️ Needs work |
| `thanos.zig` | 60% | 🚧 In progress |
| `clients/*` | 50% | 🚧 Mocked only |

Goal: 80%+ coverage before v1.0.0

## ✅ Test Checklist

### Unit Tests
- [x] Cache insertion and retrieval
- [x] Cache expiration (TTL)
- [x] LRU eviction
- [x] Retry logic with exponential backoff
- [x] Circuit breaker pattern
- [x] Error type construction
- [ ] Configuration parsing (TOML)
- [ ] Provider discovery logic

### Integration Tests
- [ ] Multi-provider routing
- [ ] Fallback chain execution
- [ ] Cache + retry integration
- [ ] Error recovery flows

### E2E Tests
- [ ] Complete request with Ollama
- [ ] Complete request with mock provider
- [ ] Failover scenario
- [ ] Performance under load

## 🎯 Writing Tests

### Example Unit Test

```zig
const std = @import("std");
const cache = @import("cache.zig");

test "cache insert and retrieve" {
    const allocator = std.testing.allocator;

    var my_cache = try cache.ResponseCache.init(allocator, 100, 3600);
    defer my_cache.deinit();

    // Insert
    const response = cache.types.CompletionResponse{
        .text = "test",
        .provider = .ollama,
        .latency_ms = 100,
        .success = true,
    };
    try my_cache.put("key", response);

    // Retrieve
    const retrieved = my_cache.get("key");
    try std.testing.expect(retrieved != null);
    defer allocator.free(retrieved.?.text);

    try std.testing.expectEqualStrings("test", retrieved.?.text);
}
```

### Example Integration Test

```zig
test "fallback chain works" {
    const allocator = std.testing.allocator;

    const config = Config{
        .fallback_providers = &.{ .anthropic, .openai, .ollama },
    };

    var ai = try Thanos.init(allocator, config);
    defer ai.deinit();

    // Should try providers in order until one succeeds
    const response = try ai.complete(.{
        .prompt = "test",
    });
    defer response.deinit(allocator);

    try std.testing.expect(response.success);
}
```

## 🔧 Test Utilities

### Mock Providers

```zig
// tests/mocks/mock_provider.zig
pub const MockProvider = struct {
    should_fail: bool = false,
    response_text: []const u8 = "mock response",
    latency_ms: u32 = 100,

    pub fn complete(self: MockProvider, request: CompletionRequest) !CompletionResponse {
        if (self.should_fail) return error.MockFailure;

        return CompletionResponse{
            .text = self.response_text,
            .provider = .ollama, // fake provider
            .latency_ms = self.latency_ms,
            .success = true,
        };
    }
};
```

### Test Fixtures

```zig
// tests/fixtures/
// - sample_config.toml
// - sample_responses.json
// - sample_errors.json
```

## 🐛 Debugging Tests

```bash
# Run with GDB
gdb --args zig test src/cache.zig

# Run with memory checking (valgrind)
valgrind zig-out/test/cache_test

# Run with AddressSanitizer
zig test src/cache.zig -fsanitize=address

# Enable all debug output
zig test src/cache.zig --test-filter "specific test" --verbose
```

## 📈 Continuous Integration

GitHub Actions runs tests on every commit:

- ✅ Unit tests (all platforms)
- ✅ Integration tests (Linux only, requires Docker)
- ✅ E2E tests (only if Ollama available)
- ✅ Memory leak detection
- ✅ Code coverage reporting

## 🤝 Contributing Tests

When adding features:

1. **Write tests first** (TDD)
2. **Aim for 80%+ coverage**
3. **Test edge cases** (errors, timeouts, etc.)
4. **Use descriptive test names**
5. **Clean up resources** (use `defer`)

### Test Naming Convention

```zig
test "cache: evicts least recently used item when full" { ... }
test "retry: exponential backoff increases delay" { ... }
test "error: fromHttpError extracts message from JSON" { ... }
```

Format: `"module: what it tests"`

## 🎓 Resources

- [Zig Testing Guide](https://ziglang.org/documentation/master/#Testing)
- [Zig Test Examples](https://ziglearn.org/chapter-1/#testing)
- [Thanos Development Guide](../docs/development.md)

# Contributing to Thanos

Thank you for your interest in contributing to Thanos! 🌌

This document provides guidelines and instructions for contributing.

## 🎯 Ways to Contribute

- 🐛 **Report bugs** - Found a bug? [Open an issue](https://github.com/ghostkellz/thanos/issues/new)
- 💡 **Suggest features** - Have an idea? [Start a discussion](https://github.com/ghostkellz/thanos/discussions)
- 🔧 **Submit pull requests** - Code contributions welcome!
- 📝 **Improve documentation** - Fix typos, add examples
- 🧪 **Add tests** - Help us reach 80%+ coverage
- ⭐ **Star the repo** - Show your support!

## 🚀 Getting Started

### 1. Fork and Clone

```bash
# Fork on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/thanos
cd thanos

# Add upstream remote
git remote add upstream https://github.com/ghostkellz/thanos
```

### 2. Set Up Development Environment

```bash
# Install Zig 0.16+ from https://ziglang.org/download/

# Build
zig build

# Run tests
zig build test

# Verify CLI works
./zig-out/bin/thanos version
```

### 3. Create a Branch

```bash
git checkout -b feature/amazing-feature

# Or for bug fixes:
git checkout -b fix/bug-description
```

## 📝 Development Workflow

### Making Changes

1. **Write tests first** (TDD approach)
   ```bash
   # Add test to appropriate file
   vim src/your_module.zig

   # Run tests
   zig test src/your_module.zig
   ```

2. **Implement the feature**
   ```zig
   // Add your code
   // Include doc comments
   ```

3. **Format code**
   ```bash
   zig fmt src/
   ```

4. **Run full test suite**
   ```bash
   zig build test
   ```

5. **Update documentation**
   - Add examples if applicable
   - Update relevant docs in `docs/`
   - Update README if adding major features

### Commit Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/):

```bash
# Format: <type>: <description>

# Types:
feat: add streaming support for responses
fix: resolve cache expiration bug
docs: update provider setup guide
style: format code with zig fmt
refactor: simplify retry logic
perf: optimize JSON parsing
test: add cache eviction tests
chore: update dependencies
```

### Pull Request Process

1. **Update your branch**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Push to your fork**
   ```bash
   git push origin feature/amazing-feature
   ```

3. **Create PR on GitHub**
   - Use a clear title (conventional commit format)
   - Describe what changed and why
   - Link related issues (`Fixes #123`)
   - Add screenshots/examples if applicable

4. **Address review feedback**
   ```bash
   # Make changes
   git add .
   git commit --amend
   git push --force origin feature/amazing-feature
   ```

## 🎨 Code Style

### Zig Style Guide

Follow [Zig style guide](https://ziglang.org/documentation/master/#Style-Guide):

```zig
// Good:
pub fn calculateFibonacci(n: usize) usize {
    if (n <= 1) return n;
    return calculateFibonacci(n - 1) + calculateFibonacci(n - 2);
}

// Use descriptive names
const max_retries = 3;

// Document public functions
/// Calculates the nth Fibonacci number.
/// Returns the Fibonacci number at position n.
pub fn fibonacci(n: usize) usize { ... }
```

### Error Handling

```zig
// Good: Explicit error handling
const result = try someOperation();

// Good: Handle specific errors
const file = std.fs.cwd().openFile("config.toml", .{}) catch |err| switch (err) {
    error.FileNotFound => return default_config,
    else => return err,
};

// Bad: Catch and ignore
const result = someOperation() catch undefined;
```

### Memory Management

```zig
// Good: Clear ownership
pub fn process(allocator: std.mem.Allocator) ![]u8 {
    const data = try allocator.alloc(u8, size);
    errdefer allocator.free(data);
    // ... populate data ...
    return data; // Caller owns this
}

// Good: Use defer for cleanup
pub fn doSomething(allocator: std.mem.Allocator) !void {
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);
    // ... use buffer ...
}
```

## 🧪 Testing Requirements

All contributions must include tests:

```zig
// Unit test example
test "feature: descriptive name" {
    const allocator = std.testing.allocator;

    // Setup
    var cache = try Cache.init(allocator, 100);
    defer cache.deinit();

    // Execute
    try cache.put("key", "value");

    // Assert
    const value = cache.get("key");
    try std.testing.expectEqualStrings("value", value.?);
}
```

### Test Coverage

- **New features**: 80%+ coverage required
- **Bug fixes**: Add regression test
- **Refactoring**: Maintain existing coverage

```bash
# Check coverage (coming soon)
zig build coverage
```

## 📚 Documentation

### Doc Comments

```zig
/// Completes a prompt using the configured AI provider.
///
/// This function:
/// 1. Checks the cache for identical prompts
/// 2. Routes to the best available provider
/// 3. Retries on transient failures
/// 4. Returns a unified response format
///
/// ## Parameters
/// - `request`: The completion request with prompt and options
///
/// ## Returns
/// A `CompletionResponse` containing the AI-generated text.
///
/// ## Errors
/// - `error.ProviderNotAvailable`: No providers are configured
/// - `error.NetworkTimeout`: Request timed out
/// - `error.InvalidApiKey`: Authentication failed
///
/// ## Example
/// ```zig
/// const response = try ai.complete(.{
///     .prompt = "Write a function",
///     .max_tokens = 500,
/// });
/// defer response.deinit(allocator);
/// ```
pub fn complete(self: *Thanos, request: CompletionRequest) !CompletionResponse { ... }
```

### Updating Docs

If your PR affects user-facing behavior:

1. Update relevant files in `docs/`
2. Add examples to `examples/`
3. Update README.md if adding major features
4. Update CHANGELOG.md

## 🔍 Code Review Process

### What We Look For

✅ **Good**:
- Clear, focused changes
- Tests included
- Documentation updated
- Follows conventions
- No breaking changes (or clearly marked)

❌ **Issues**:
- Large, unfocused PRs
- Missing tests
- Unclear purpose
- Breaking changes without discussion

### Review Timeline

- Initial review: Within 48 hours
- Follow-up reviews: Within 24 hours
- Merge: After 1+ approvals and CI passes

## 🐛 Bug Reports

### Before Reporting

1. Search existing issues
2. Try latest `main` branch
3. Gather debugging info:
   ```bash
   thanos version
   zig version
   thanos discover
   ```

### Bug Report Template

```markdown
**Describe the bug**
A clear description of the bug.

**To Reproduce**
Steps to reproduce:
1. Run command `thanos complete "..."`
2. See error

**Expected behavior**
What you expected to happen.

**Environment**
- OS: [e.g., Ubuntu 22.04]
- Zig version: [e.g., 0.16.0]
- Thanos version: [e.g., 0.1.0]
- Provider: [e.g., Ollama]

**Additional context**
Any other relevant information.
```

## 💡 Feature Requests

### Before Requesting

1. Check existing discussions
2. Consider if it fits Thanos's scope
3. Think about implementation complexity

### Feature Request Template

```markdown
**Problem**
What problem does this solve?

**Proposed Solution**
How should it work?

**Alternatives Considered**
Other approaches you've thought about.

**Impact**
Who benefits? What's the use case?
```

## 🏗️ Project Structure

```
thanos/
├── src/                    # Source code
│   ├── root.zig           # Public API
│   ├── thanos.zig         # Core orchestration
│   ├── clients/           # Provider clients
│   └── ...
├── docs/                   # User documentation
├── examples/               # Code examples
├── tests/                  # Test suite
├── benchmarks/             # Performance benchmarks
└── archive/                # Internal notes (not public)
```

## 🎯 Good First Issues

New to the project? Look for issues labeled `good-first-issue`:

- Documentation improvements
- Adding examples
- Writing tests
- Small bug fixes
- Code cleanup

## 📞 Getting Help

- **Questions**: [GitHub Discussions](https://github.com/ghostkellz/thanos/discussions)
- **Chat**: [Discord](https://discord.gg/ghoststack)
- **Email**: dev@ghoststack.io

## 🙏 Recognition

Contributors are recognized in:
- `CONTRIBUTORS.md`
- Release notes
- Project README

Thank you for contributing to Thanos! 🌌

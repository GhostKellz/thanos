# AI-Powered Code Review Architecture

**Granular, context-aware code reviews with multi-provider support**

---

## Overview

Design for comprehensive AI code review functionality in Thanos that:
- Leverages multiple AI providers (Ollama, GPT-5, Anthropic Claude, Grok)
- Provides context-aware, granular feedback
- Works across all Thanos integrations (thanos.grim, thanos.nvim, phantom.grim)
- Supports different review depths and focus areas

---

## Architecture

### High-Level Design

```
┌────────────────────────────────────────────────┐
│           User Interface Layer                 │
│  (thanos.grim / thanos.nvim / phantom.grim)   │
└─────────────────┬──────────────────────────────┘
                  │
┌─────────────────▼──────────────────────────────┐
│         Thanos Core (Zig)                      │
│  ┌──────────────────────────────────────────┐ │
│  │   Code Review Orchestrator               │ │
│  │  - Request routing                       │ │
│  │  - Context gathering                     │ │
│  │  - Response aggregation                  │ │
│  │  - Granular filtering                    │ │
│  └─────────────────┬────────────────────────┘ │
└────────────────────┼───────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐    ┌──────────▼─────────┐
│ Provider Pool  │    │  Context Engine    │
│ - Ollama       │    │  - File analysis   │
│ - GPT-5        │    │  - Git history     │
│ - Claude       │    │  - Dependencies    │
│ - Grok         │    │  - Project context │
└────────────────┘    └────────────────────┘
```

---

## Core Components

### 1. Code Review Orchestrator (Thanos Core)

**Location**: `/data/projects/thanos/src/review/orchestrator.zig`

**Responsibilities**:
- Receive review requests from editor integrations
- Gather code context (file content, git history, dependencies)
- Route requests to appropriate AI providers
- Aggregate and rank feedback
- Apply granular filtering (severity, category, confidence)

**API**:
```zig
pub const ReviewRequest = struct {
    code: []const u8,
    language: []const u8,
    file_path: ?[]const u8,
    context: ReviewContext,
    options: ReviewOptions,
};

pub const ReviewContext = struct {
    git_diff: ?[]const u8,
    git_history: []GitCommit,
    dependencies: []Dependency,
    project_structure: ProjectInfo,
    recent_changes: []FileChange,
};

pub const ReviewOptions = struct {
    providers: []Provider,  // Which AIs to use
    depth: ReviewDepth,     // quick/normal/deep
    focus: []ReviewCategory,// bugs/security/performance/style
    granularity: Granularity, // file/function/line
    confidence_threshold: f32, // Filter low-confidence feedback
};

pub const ReviewDepth = enum {
    quick,   // Fast, surface-level (Ollama)
    normal,  // Balanced (Ollama + one cloud provider)
    deep,    // Thorough (all providers, consensus)
};

pub const ReviewCategory = enum {
    bugs,
    security,
    performance,
    memory_safety,
    concurrency,
    error_handling,
    style,
    maintainability,
    documentation,
    testing,
};

pub const Granularity = enum {
    file,      // Whole file review
    function,  // Per-function review
    line,      // Line-by-line review
};

pub const ReviewResponse = struct {
    issues: []Issue,
    suggestions: []Suggestion,
    metrics: ReviewMetrics,
    providers_used: []Provider,
};

pub const Issue = struct {
    severity: Severity,
    category: ReviewCategory,
    location: Location,
    message: []const u8,
    explanation: []const u8,
    fix_suggestion: ?[]const u8,
    confidence: f32,  // 0.0-1.0
    provider: Provider,
};

pub const Location = struct {
    file: []const u8,
    line_start: usize,
    line_end: usize,
    column_start: usize,
    column_end: usize,
};
```

---

### 2. Context Engine

**Location**: `/data/projects/thanos/src/review/context.zig`

**Purpose**: Gather rich context for AI reviewers

**Context Types**:

#### A. File-Level Context
```zig
pub const FileContext = struct {
    content: []const u8,
    language: []const u8,
    path: []const u8,
    size: usize,
    dependencies: []const u8,  // imports/includes
    exports: []const u8,        // public functions/types
};
```

#### B. Git Context
```zig
pub const GitContext = struct {
    current_diff: ?[]const u8,
    recent_commits: []GitCommit,
    blame_info: []BlameLine,
    branch: []const u8,
};

pub const GitCommit = struct {
    hash: []const u8,
    author: []const u8,
    date: i64,
    message: []const u8,
    files_changed: []const u8,
};
```

#### C. Project Context
```zig
pub const ProjectContext = struct {
    name: []const u8,
    language: []const u8,
    framework: ?[]const u8,
    build_system: []const u8,
    dependencies: []Dependency,
    file_tree: []const u8,
    readme: ?[]const u8,
};
```

#### D. Historical Context
```zig
pub const HistoricalContext = struct {
    common_issues: []PastIssue,  // Issues in similar code before
    fix_patterns: []FixPattern,   // How similar issues were fixed
    code_churn: []ChurnMetric,   // Frequently changed code (bug-prone)
};
```

**Context Gathering Strategy**:
```zig
pub fn gatherContext(allocator: Allocator, request: ReviewRequest) !ReviewContext {
    // 1. Parse code to extract structure
    const ast = try parseCode(request.code, request.language);

    // 2. Get git context if available
    const git_ctx = if (request.file_path) |path|
        try getGitContext(path)
    else
        null;

    // 3. Extract dependencies
    const deps = try extractDependencies(ast);

    // 4. Get project structure
    const project = try getProjectInfo(request.file_path);

    // 5. Load historical data
    const history = try getHistoricalContext(request.file_path);

    return ReviewContext{
        .git_diff = if (git_ctx) |g| g.current_diff else null,
        .git_history = if (git_ctx) |g| g.recent_commits else &.{},
        .dependencies = deps,
        .project_structure = project,
        .recent_changes = if (history) |h| h.code_churn else &.{},
    };
}
```

---

### 3. Provider-Specific Reviewers

Each AI provider has strengths. Route different review aspects to appropriate providers:

#### Ollama (Local, Fast)
**Best For**: Quick initial scan, obvious bugs
```zig
pub const OllamaReviewer = struct {
    pub fn review(self: *OllamaReviewer, request: ReviewRequest) !ReviewResponse {
        // Use local models: codellama, deepseek-coder
        // Fast turnaround (<2s)
        // Focus: syntax errors, obvious bugs, simple style issues
    }
};
```

**Prompt Strategy**:
```
Review this {language} code for obvious issues:
- Syntax errors
- Null pointer dereferences
- Off-by-one errors
- Unused variables
- Missing error handling

Code:
```{language}
{code}
```

List issues in format:
LINE: <number> | SEVERITY: <low/medium/high> | ISSUE: <description>
```

#### GPT-5 Codex (Advanced Reasoning)
**Best For**: Complex logic, algorithms, architecture
```zig
pub const GPT5Reviewer = struct {
    pub fn review(self: *GPT5Reviewer, request: ReviewRequest) !ReviewResponse {
        // Use GPT-5 for complex analysis
        // Focus: algorithm correctness, edge cases, concurrency issues
    }
};
```

**Prompt Strategy**:
```
You are an expert code reviewer. Analyze this {language} code for:
1. Algorithmic correctness
2. Edge case handling
3. Concurrency issues (race conditions, deadlocks)
4. Complex logic errors

Context:
- File: {file_path}
- Recent changes: {git_diff}
- Dependencies: {dependencies}

Code:
```{language}
{code}
```

Provide detailed analysis with:
- Issue severity (critical/high/medium/low)
- Line numbers
- Explanation
- Suggested fix
```

#### Claude (Anthropic) - Best Explainer
**Best For**: Security, best practices, refactoring
```zig
pub const ClaudeReviewer = struct {
    pub fn review(self: *ClaudeReviewer, request: ReviewRequest) !ReviewResponse {
        // Use Claude for security and best practices
        // Focus: security vulnerabilities, code smells, refactoring opportunities
    }
};
```

**Prompt Strategy**:
```
Review this {language} code for security and best practices:

Security concerns:
- Input validation
- SQL injection / command injection
- XSS vulnerabilities
- Authentication/authorization issues
- Cryptography misuse

Best practices:
- Idiomatic {language} code
- Design patterns
- Error handling conventions
- Memory safety

Code:
```{language}
{code}
```

For each issue, explain:
1. What the problem is
2. Why it's a problem
3. How to fix it
4. Alternative approaches
```

#### Grok (xAI) - Fast Alternative
**Best For**: Performance, optimization
```zig
pub const GrokReviewer = struct {
    pub fn review(self: *GrokReviewer, request: ReviewRequest) !ReviewResponse {
        // Use Grok for performance analysis
        // Focus: algorithm complexity, memory usage, bottlenecks
    }
};
```

**Prompt Strategy**:
```
Analyze this {language} code for performance:

Performance aspects:
- Time complexity (Big-O notation)
- Space complexity
- Unnecessary allocations
- Inefficient algorithms
- Hotspot identification

Code:
```{language}
{code}
```

Suggest optimizations with:
- Current complexity
- Optimized complexity
- Specific changes
- Trade-offs
```

---

### 4. Granular Filtering & Ranking

After gathering feedback from multiple providers, filter and rank:

```zig
pub fn aggregateReviews(allocator: Allocator, responses: []ReviewResponse) !ReviewResponse {
    var all_issues = std.ArrayList(Issue).init(allocator);

    // 1. Collect all issues from all providers
    for (responses) |response| {
        try all_issues.appendSlice(response.issues);
    }

    // 2. Deduplicate (same issue from multiple providers)
    const unique_issues = try deduplicateIssues(allocator, all_issues.items);

    // 3. Rank by severity and confidence
    std.sort.block(Issue, unique_issues, {}, compareIssues);

    // 4. Apply confidence threshold
    const filtered = try filterByConfidence(allocator, unique_issues, 0.7);

    return ReviewResponse{
        .issues = filtered,
        .suggestions = try aggregateSuggestions(responses),
        .metrics = try calculateMetrics(filtered),
        .providers_used = try listProvidersUsed(responses),
    };
}

fn compareIssues(context: void, a: Issue, b: Issue) bool {
    _ = context;

    // Sort by severity first
    if (@intFromEnum(a.severity) != @intFromEnum(b.severity)) {
        return @intFromEnum(a.severity) > @intFromEnum(b.severity);
    }

    // Then by confidence
    return a.confidence > b.confidence;
}

fn deduplicateIssues(allocator: Allocator, issues: []Issue) ![]Issue {
    var unique = std.ArrayList(Issue).init(allocator);

    for (issues) |issue| {
        var is_duplicate = false;

        for (unique.items) |existing| {
            // Same location and similar message = duplicate
            if (locationsEqual(issue.location, existing.location) and
                messagesSimilar(issue.message, existing.message))
            {
                // Boost confidence if multiple providers agree
                existing.confidence = @min(1.0, existing.confidence + 0.2);
                is_duplicate = true;
                break;
            }
        }

        if (!is_duplicate) {
            try unique.append(issue);
        }
    }

    return unique.toOwnedSlice();
}
```

---

## Integration Points

### 1. Thanos Core API

**Location**: `/data/projects/thanos/src/review/api.zig`

```zig
pub const ReviewAPI = struct {
    allocator: Allocator,
    orchestrator: *ReviewOrchestrator,
    context_engine: *ContextEngine,
    providers: ProviderPool,

    pub fn reviewCode(self: *ReviewAPI, request: ReviewRequest) !ReviewResponse {
        // 1. Gather context
        const context = try self.context_engine.gather(request);

        // 2. Select providers based on options
        const providers = try self.selectProviders(request.options);

        // 3. Execute reviews in parallel
        var responses = std.ArrayList(ReviewResponse).init(self.allocator);
        defer responses.deinit();

        for (providers) |provider| {
            const response = try provider.review(request, context);
            try responses.append(response);
        }

        // 4. Aggregate and filter
        return try aggregateReviews(self.allocator, responses.items);
    }

    // Export for C FFI (used by editor plugins)
    export fn thanos_review_code(
        code: [*:0]const u8,
        language: [*:0]const u8,
        options_json: [*:0]const u8,
    ) callconv(.C) [*:0]const u8 {
        // Marshal C strings to Zig
        // Call reviewCode()
        // Serialize result to JSON
        // Return as C string
    }
};
```

---

### 2. Editor Integration (thanos.grim / phantom.grim)

**Location**: `/data/projects/thanos.grim/src/root.zig`

```zig
// Add to existing thanos_grim plugin

pub export fn thanos_review_detailed(
    code: [*:0]const u8,
    options: [*:0]const u8,
) callconv(.c) [*:0]const u8 {
    const code_str = std.mem.span(code);
    const options_str = std.mem.span(options);

    // Parse options JSON
    const review_opts = parseReviewOptions(options_str) catch {
        return "error: invalid options";
    };

    // Call Thanos review API
    const result = thanos_api.reviewCode(.{
        .code = code_str,
        .language = detectLanguage(),
        .file_path = getCurrentFilePath(),
        .context = .{},  // Auto-gathered
        .options = review_opts,
    }) catch |err| {
        return formatError(err);
    };

    // Format as JSON
    return formatReviewResponse(result);
}
```

**Ghostlang Plugin** (`/data/projects/phantom.grim/plugins/ai/thanos.gza`):

```lua
-- Add to existing thanos.gza

-- Deep AI code review with granular options
function thanos_review_detailed_handler(args)
    if not thanos_initialized then
        show_error("Thanos not initialized")
        return
    end

    -- Get review options from user
    local options = prompt_review_options() or {
        providers = {"ollama", "claude"},  -- Use Ollama + Claude
        depth = "normal",
        focus = {"bugs", "security", "performance"},
        granularity = "function",
        confidence_threshold = 0.7,
    }

    -- Get current buffer/selection
    local code = get_buffer_text() or get_visual_selection()
    local language = get_buffer_filetype()

    -- Show progress
    show_message("🔍 Reviewing code with " .. table.concat(options.providers, " + ") .. "...")

    -- Call native review function
    local options_json = json.encode(options)
    local result_json = call_native("thanos_review_detailed", options_json)
    local result = json.decode(result_json)

    -- Display results in formatted window
    display_review_results(result)
end

function display_review_results(result)
    -- Create review results window
    local win = create_split_window("AI Code Review", "vertical", 50)

    -- Format output
    local output = format_review_output(result)

    set_window_text(win, output)

    -- Add keybindings
    register_window_keybind(win, "<CR>", "jump_to_issue")
    register_window_keybind(win, "f", "apply_fix")
    register_window_keybind(win, "q", "close_window")
end
```

---

### 3. Neovim Integration (thanos.nvim)

**Location**: `/data/projects/thanos.nvim/lua/thanos/review.lua`

```lua
local M = {}

function M.review_code(opts)
    opts = vim.tbl_deep_extend("force", {
        providers = {"ollama", "claude"},
        depth = "normal",
        focus = {"bugs", "security"},
        granularity = "function",
        confidence_threshold = 0.7,
    }, opts or {})

    -- Get code
    local code = get_buffer_or_selection()
    local filetype = vim.bo.filetype

    -- Call Thanos native API
    local result = vim.fn.thanos_review({
        code = code,
        language = filetype,
        options = opts,
    })

    -- Display in quickfix or floating window
    display_review_results(result)
end

-- Command
vim.api.nvim_create_user_command("ThanosReviewDeep", function()
    M.review_code({ depth = "deep", providers = {"ollama", "claude", "gpt5"} })
end, {})

return M
```

---

## Usage Examples

### Example 1: Quick Review (Ollama Only)

```vim
" In Vim/Neovim
:ThanosReview

" Or in Grim
:ThanosReview

" Uses:
" - Provider: Ollama (fast, local)
" - Depth: quick
" - Focus: bugs, obvious issues
" - Time: ~2s
```

### Example 2: Security Review (Claude)

```vim
:ThanosReviewSecurity

" Uses:
" - Provider: Claude (best for security)
" - Depth: deep
" - Focus: security, vulnerabilities
" - Time: ~10s
```

### Example 3: Performance Review (Grok)

```vim
:ThanosReviewPerformance

" Uses:
" - Provider: Grok (performance focus)
" - Depth: normal
" - Focus: performance, optimization
" - Time: ~8s
```

### Example 4: Comprehensive Review (All Providers)

```vim
:ThanosReviewDeep

" Uses:
" - Providers: Ollama + GPT-5 + Claude + Grok
" - Depth: deep
" - Focus: all categories
" - Aggregates and ranks feedback
" - Time: ~15-20s
```

---

## Implementation Plan

### Phase 1: Core Review Engine (Thanos)
**Location**: `/data/projects/thanos/`
1. ✅ Create `src/review/orchestrator.zig`
2. ✅ Create `src/review/context.zig`
3. ✅ Create `src/review/providers/ollama.zig`
4. ✅ Create `src/review/providers/gpt5.zig`
5. ✅ Create `src/review/providers/claude.zig`
6. ✅ Create `src/review/providers/grok.zig`
7. ✅ Create `src/review/aggregator.zig`
8. ✅ Export C API: `thanos_review_code()`

### Phase 2: Editor Integrations
**Locations**: `/data/projects/thanos.grim/`, `/data/projects/thanos.nvim/`, `/data/projects/phantom.grim/`
1. ✅ Add `thanos_review_detailed()` to thanos.grim
2. ✅ Update Ghostlang plugin with review commands
3. ✅ Add Neovim Lua API
4. ✅ Create review results UI

### Phase 3: Advanced Features
1. ✅ Historical context (learn from past reviews)
2. ✅ Custom review rules
3. ✅ Team review templates
4. ✅ Cost tracking & optimization

---

## Configuration Example

```toml
# ~/.config/thanos/config.toml

[review]
default_providers = ["ollama", "claude"]
default_depth = "normal"
confidence_threshold = 0.7

[review.providers.ollama]
enabled = true
model = "deepseek-coder:6.7b"
timeout = 5

[review.providers.gpt5]
enabled = true
api_key = "sk-..."
model = "gpt-5-turbo"

[review.providers.claude]
enabled = true
api_key = "sk-ant-..."
model = "claude-3-5-sonnet-20241022"

[review.providers.grok]
enabled = false
api_key = "xai-..."

[review.focus]
# Which categories to enable by default
bugs = true
security = true
performance = true
style = false  # Disable style checks by default

[review.granularity]
default = "function"  # file/function/line

[review.cost_limits]
max_tokens_per_review = 10000
max_cost_per_day = 5.00  # USD
```

---

## Next Steps

1. **Implement Core Engine** in `/data/projects/thanos/src/review/`
2. **Add FFI Exports** for editor integrations
3. **Update thanos.grim** with review commands
4. **Update phantom.grim** with review UI
5. **Update thanos.nvim** with review API
6. **Test & Iterate** on real codebases

This architecture provides granular, context-aware AI code reviews with multi-provider support across all Thanos integrations!

---

**Author**: Ghost Stack + Claude Code
**Date**: 2025-10-19
**Status**: Design Complete - Ready for Implementation

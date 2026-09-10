# MCPContextEngine

[![CI](https://github.com/Dev10-sys/MCPContextEngine/actions/workflows/ci.yml/badge.svg)](https://github.com/Dev10-sys/MCPContextEngine/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%2015%2B%20%7C%20iOS%2018%2B%20%7C%20Linux-blue.svg)](https://apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift Package Index](https://img.shields.io/badge/SPI-v0.1.0-brightgreen.svg)](https://swiftpackageindex.com)

`MCPContextEngine` is a Swift runtime middleware library for context-aware Model Context Protocol (MCP) orchestration. It routes relevant tools from large multi-server catalogs, accounts for prompt context headroom, deterministically reduces oversized tool results within strict token budgets, and exposes structured telemetry for debugging and evaluation.

```
MCP Servers
    │
    ▼
┌───────────────────────────────────────┐
│           MCPContextEngine            │
│                                       │
│  • MCPToolRegistry (Multi-server)     │
│  • ToolRouter (Lexical scoring)       │
│  • ContextBudgetManager (Headroom)    │
│  • ResultReducer (Structural pruning) │
└──────────────────┬────────────────────┘
                   │
                   ▼
       Model / Application Runtime
       (Foundation Models, LLMs)
```

---

## Scope

`MCPContextEngine` is a middleware layer designed for an agent turn. It does not implement a Large Language Model, host MCP servers, or provide an autonomous multi-step agent planner.

### What it provides
- **Deterministic Tool Routing**: Multi-signal lexical tool scoring (`ToolRouter`, `ToolScorer`) evaluating name matches, description semantics, and query keywords under strict schema token constraints.
- **Context Headroom Accounting**: Dynamic tracking of token allocations for system instructions, conversation turns, selected tool schemas, and response buffers.
- **Result Reduction**: Structural compaction for JSON and progressive head/tail truncation for text payloads with a provider-relative hard ceiling.
- **MCP Stdio Client Integration**: Multi-server catalog registry and execution dispatcher over standard I/O child processes using the official Swift MCP SDK.
- **Apple Foundation Models Bridge**: Availability-aware `Tool` protocol conformance (`AppleMCPTool`), dynamic schema generation (`DynamicGenerationSchema`), and `LanguageModelSession` execution adapters.
- **Observability Telemetry**: Structured JSON telemetry records (`EngineTelemetryEvent`) and a local developer observability console.

### Current limitations
- Tool routing uses deterministic lexical scoring; it does not embed a vector database or semantic embedding model.
- MCP client transport currently focuses on standard I/O (`stdio`); HTTP transport abstractions are not yet implemented.
- JSON Schema mapping covers the common MCP schema subset (primitive types, descriptions, enums, array items, and required fields).
- Token budgeting is exact relative to the configured `TokenProvider` (such as the default `CalibratedTokenProvider` or platform-native providers).
- The convenience `process` facade executes one primary routed tool per turn; applications coordinating multi-tool plans can invoke selected tools independently.

---

## Architecture

The engine pipeline coordinates five sequential phases for each turn:

```
discover ──▶ route ──▶ execute ──▶ reduce ──▶ emit telemetry
```

### Modules

- **`MCPContextEngineCore`**: Independent foundational module containing tool routing (`ToolRouter`), budget accounting (`ContextBudgetManager`), structural result reduction (`ResultReducer`, `JSONReducer`, `TextReducer`), and telemetry models (`EngineTelemetryEvent`).
- **`MCPContextEngineMCP`**: MCP protocol integration layer built on the official Swift MCP SDK. Provides `MCPToolRegistry`, `StdioMCPClientAdapter`, argument validation, and `MCPToolExecutor`.
- **`MCPContextEngineFoundationModels`**: Apple platform integration layer providing `AppleMCPTool` (`Tool` protocol conformance under macOS 15+ / iOS 18+), dynamic schema bridging, and `FoundationModelsTokenProvider`.
- **`MCPContextEngineDemo`**: Interactive command-line executable demonstrating live GitHub issue retrieval, routing, compaction, and telemetry streaming.

---

## Installation

Add `MCPContextEngine` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/Dev10-sys/MCPContextEngine.git",
        from: "0.1.0"
    )
]
```

Add the target products required for your application:

```swift
.target(
    name: "MyAgentTarget",
    dependencies: [
        .product(name: "MCPContextEngineCore", package: "MCPContextEngine"),
        .product(name: "MCPContextEngineMCP", package: "MCPContextEngine"),
        // Optional: for Apple Foundation Models support
        .product(name: "MCPContextEngineFoundationModels", package: "MCPContextEngine")
    ]
)
```

---

## Quick Start

The convenience facade executes the complete middleware turn in a single call:

```swift
import MCPContextEngineCore
import MCPContextEngineMCP

// 1. Initialize engine with a 4,096-token on-device context budget
let engine = MCPContextEngine(capacity: 4096)

// 2. Discover available tools from your catalog
let availableTools: [MCPToolDescriptor] = catalog.allTools()

// 3. Process turn: score tools, calculate headroom, execute, and compact
let result = try await engine.process(
    task: "Find open Swift concurrency issues",
    availableTools: availableTools
) { tool in
    // Dispatch tool execution through your MCP client
    try await client.callTool(name: tool.name, arguments: [
        "query": "is:issue is:open label:concurrency"
    ])
}

// 4. Inspect results
print("Selected tools: \(result.selectedTools.map(\.name))")
print("Compacted result: \(result.reducedResult)")
print("Budget compliant: \(result.fitsBudget)")
```

---

## MCP Integration

### Multi-Server Tool Registry

`MCPToolRegistry` coordinates multiple heterogeneous MCP servers (e.g. GitHub, Filesystem, Database) and namespaces tool descriptors by `serverId:name` to prevent collisions:

```swift
let registry = MCPToolRegistry()

// Register stdio client adapters
let githubClient = StdioMCPClientAdapter(
    serverId: "github",
    command: "/usr/local/bin/github-mcp-server"
)
await registry.registerServer(githubClient)

// Concurrently discover and catalog all tools (sorted deterministically)
let discoveredTools = try await registry.discoverAllTools()
```

### Secure Execution & Parameter Validation

`MCPToolExecutor` validates arguments against the tool's `ToolInputSchema` (enforcing required parameters, primitive types, and enum choices) and enforces optional execution allowlists:

```swift
let executor = MCPToolExecutor(registry: registry)

// Optional security allowlist produced by the router
let approvedToolIds = Set(result.selectedTools.map(\.id))

// Executes with argument validation and authorization checks
let rawOutput = try await executor.execute(
    descriptor: selectedTool,
    arguments: ["query": "concurrency", "limit": 10],
    approvedTools: approvedToolIds
)
```

> [!NOTE]
> The current client adapter normalizes textual MCP tool content into `String`; richer binary content types (images, audio) are not yet surfaced by the public execution API.

### Demo Data Path vs. Production MCP Transport Path

- **Interactive Demo Path**: The CLI demonstration uses an in-memory client (`MockMCPClient`) populated with live GitHub REST API responses to showcase real-world data compaction and target preservation.
- **Production MCP Transport Path**: Production deployments use `StdioMCPClientAdapter`, managing child process pipes and asynchronous JSON-RPC protocol messages via the official Swift MCP SDK.

---

## Apple Foundation Models Integration

When building for Apple platforms (`macOS 15.0+`, `iOS 18.0+`), `MCPContextEngineFoundationModels` bridges discovered MCP tools into native Apple Intelligence components:

- **Native Tool Conformance**: `AppleMCPTool` conforms directly to `FoundationModels.Tool` with typed dynamic arguments and `call(arguments:)`.
- **Dynamic Schema Generation**: Translates common-case MCP JSON Schemas into `DynamicGenerationSchema` / `GenerationSchema` at runtime so the model can inspect parameters without compile-time Swift schemas.
- **Runtime-Aware Introspection**: Queries `SystemLanguageModel.default.tokenCount(for:)` and `SystemLanguageModel.default.contextSize` when available on supported Apple Intelligence runtimes.

> [!IMPORTANT]
> Live `LanguageModelSession` execution requires an Apple Intelligence-capable device with model assets installed. Hosted CI environments verify tool protocol conformance, schema generation, and cross-platform bridge adapters.

---

## Design Goals

- **Deterministic Behavior**: Lexical routing and structural reduction produce reproducible outcomes given identical inputs.
- **Provider-Relative Accounting**: All token limits and budget checks are strictly calculated relative to the configured `TokenProvider`.
- **Non-Destructive Compaction**: Raw tool responses are retained in `ReductionResult.originalData` alongside reduced content for auditing and inspection.
- **Explicit Tool Identity**: Tools are namespaced by origin server (`serverId:name`) to eliminate cross-server ambiguities.
- **Swift 6 Concurrency**: Designed and validated under Swift 6 strict concurrency checks without data race warnings.
- **Observable Decisions**: Every turn produces a structured `EngineTelemetryEvent` capturing latency, token counts, and routing metrics.

---

## Guarantees and Heuristics

### Guarantees
- **Context Headroom Compliance**: The reducer enforces a provider-relative hard ceiling on every completed reduction. If structural pruning is insufficient, deterministic boundary clamping guarantees that `reducedTokens <= availableBudgetTokens`.
- **Audit Immutability**: The unmodified raw MCP server response is retained in memory and accessible via `ReductionResult.originalData`.
- **Tool Disambiguation**: Tool identifiers are namespaced (`serverId:name`). Calling an ambiguous bare tool name throws `ExecutionSecurityError.ambiguousTool`.
- **Allowlist Enforcement**: When an execution allowlist is supplied (`approvedTools`), `MCPToolExecutor` blocks unauthorized tool invocations before process dispatch.

### Heuristics
- **Relevance Scoring**: Tool routing is based on deterministic lexical matching (name tokens, description overlap, query keywords) rather than semantic vector embeddings.
- **Schema Token Estimation**: Schema token counts are calculated using canonical structural representations with the configured `TokenProvider`.
- **Target Preservation**: Default entity preservation verifies keyword retention in the compacted output.
- **JSON Compaction**: Structural reduction prunes null values, empty collections, and non-prioritized metadata keys while preserving high-value identifier fields and original array element order.

---

## Benchmarks

The deterministic benchmark harness evaluates context compliance and tool routing across 10 developer scenarios (covering issue searches, database queries, release notes, and diagnostics):

*Representative run from deterministic benchmark fixtures (timings vary by host machine):*
```
====================================================
             MCP CONTEXT ENGINE BENCHMARK
====================================================
Scenario: GitHub Issue Search (Concurrency)
Discovered tools: 37 (across 6 registered servers)
---------------- BASELINE (Naive MCP) --------------
Tools exposed:        37
Schema tokens:        ~962
Result tokens:        ~21,850
Total context:        ~24,512 tokens
Context overflow:     YES (Deficit: ~20,416 tokens)
Context-fit success:  0% (Exceeds 4,096-token window)
---------------- ENGINE (MCPContextEngine) ----------
Tools exposed:        4 (-89.2% pruned)
Schema tokens:        ~148 tokens (-84.6%)
Raw result tokens:    ~21,850 tokens (preserved for audit)
Reduced tokens:       ~1,600 tokens (-92.7% compaction)
Total context:        ~3,448 tokens
Context overflow:     NO (Fits within 4,096 budget)
Target preserved:     YES (Issue #92004 retained)
Context-fit success:  100% (Within budget headroom)
Expected tool:        github_search_issues (Rank #1)
---------------- LATENCY OVERHEAD ------------------
Routing latency:      ~11 ms
Reduction latency:    ~42 ms
Total overhead:       ~53 ms
====================================================
```

### Scenario Test Matrix

| Scenario ID | Task Query | Baseline Overflow | Engine Budget Compliant | Target Preserved | Expected Tool Selected | Context-Fit Success |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `scenario-1-concurrency` | Find open Swift concurrency data race issues | ❌ Overflow (+20K) | ✅ FITS | ✅ YES (#92004) | ✅ `github_search_issues` | 100% |
| `scenario-2-memory-leak` | Search memory leak in async stream actor buffer | ❌ Overflow (+18K) | ✅ FITS | ✅ YES (#92010) | ✅ `github_search_issues` | 100% |
| `scenario-3-file-read` | Read filesystem config json from repository root | ❌ Overflow (+12K) | ✅ FITS | ✅ YES (config.json) | ✅ `fs_read_file` | 100% |
| `scenario-4-slack-alert` | Send Slack alert notification message to deploy channel | ❌ Overflow (+8K) | ✅ FITS | ✅ YES (alert msg) | ✅ `slack_post_message` | 100% |
| `scenario-5-db-query` | Query database users table where active equals true | ❌ Overflow (+15K) | ✅ FITS | ✅ YES (user records) | ✅ `db_query` | 100% |
| `scenario-6-pr-review` | List pull requests open for review on main branch | ❌ Overflow (+14K) | ✅ FITS | ✅ YES (PR #404) | ✅ `github_list_pull_requests` | 100% |
| `scenario-7-docker-logs` | Fetch container logs and diagnostic crash trace | ❌ Overflow (+16K) | ✅ FITS | ✅ YES (crash trace) | ✅ `monitoring_get_logs` | 100% |
| `scenario-8-release-notes` | Generate changelog release notes for version 2.0 tag | ❌ Overflow (+11K) | ✅ FITS | ✅ YES (v2.0 notes) | ✅ `github_create_release` | 100% |
| `scenario-9-auth-token` | Validate authentication token permissions and scope | ❌ Overflow (+9K) | ✅ FITS | ✅ YES (oauth scopes) | ✅ `db_verify_token` | 100% |
| `scenario-10-benchmark-perf` | Measure performance latency and memory footprint | ❌ Overflow (+13K) | ✅ FITS | ✅ YES (latency samples) | ✅ `monitoring_get_metrics` | 100% |

---

## Developer Observability Console

The repository includes an optional local developer observability console in `dashboard/`:

1. Start the local dashboard server (bound to loopback `127.0.0.1:3000` with a 1MB payload cap):
```bash
python3 dashboard/server/server.py
```
2. Open `http://127.0.0.1:3000` in your browser.
3. Run the demo or execute the engine pipeline:
```bash
swift run MCPContextEngineDemo
```
The console automatically updates via live telemetry:
- Discovered vs. routed tools with score breakdowns
- Live context allocation and headroom gauges
- Compaction ratios and latency metrics
- Formatted Codable JSON telemetry records

---

## Development & Verification

### Prerequisites
- Swift 6.0+ toolchain
- Node.js 22+ (for Everything MCP Server integration tests)
- Python 3.8+ (for optional developer console)

### Build and Test Commands

```bash
# Build release configuration
swift build -c release

# Run full test suite
swift test --enable-code-coverage

# Run live stdio MCP integration tests
swift test --filter LiveEverythingServerTests

# Run deterministic benchmark suite
swift test --filter TaskSuccessBenchmarkTests

# Run interactive demonstration CLI
swift run MCPContextEngineDemo
```

---

## Security

Please review [SECURITY.md](SECURITY.md) for details regarding our security architecture, execution boundaries, delimiter sanitization, and private vulnerability reporting via GitHub Security Advisories.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

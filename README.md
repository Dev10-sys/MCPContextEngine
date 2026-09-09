# MCPContextEngine

[![CI](https://github.com/Dev10-sys/MCPContextEngine/actions/workflows/ci.yml/badge.svg)](https://github.com/Dev10-sys/MCPContextEngine/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%2015%2B%20%7C%20iOS%2018%2B%20%7C%20Linux-blue.svg)](https://apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A high-performance runtime middleware layer for Swift that bridges **Model Context Protocol (MCP)** servers with **Apple Foundation Models** and LLM runtimes. It performs application-side, task-aware context orchestration: routing relevant tools from large multi-server catalogs, tracking live context headroom, compacting oversized payloads with strict mathematical token guarantees, and streaming real-time telemetry to developer dashboards.

```
              User Task / Prompt
                      │
                      ▼
           ┌───────────────────────┐
           │   MCPContextEngine    │
           └──────────┬────────────┘
                      │
       ┌──────────────┼──────────────┐
       ▼              ▼              ▼
 ┌───────────┐ ┌──────────────┐ ┌───────────┐
 │Tool Router│ │Context Budget│ │  Result   │
 │  Scorer   │ │   Manager    │ │  Reducer  │
 └─────┬─────┘ └──────┬───────┘ └─────┬─────┘
       │               │               │
       └───────────────┼───────────────┘
                       │
               ┌───────────────┐
               │  MCP Servers  │
               │(GitHub, etc.) │
               └───────┬───────┘
                       │
            ┌─────────────────────┐
            │  Foundation Model / │
            │   Apple Utilities   │
            └──────────┬──────────┘
                       │
                 Final Answer
```

---

## Core Value Proposition

Connecting 5–10 MCP servers (GitHub, Filesystem, Slack, Database, Everything) exposes 40–60+ tool schemas into the model prompt. Each schema carries property descriptions, nested objects, and validation rules, consuming 1,200–2,500+ tokens before conversation history or instructions are counted.

When a selected tool executes and returns raw JSON — repository issue searches, database tables, build logs — payloads frequently exceed 20,000+ tokens. On-device models with a 4,096-token context window crash, reject the prompt, or truncate essential context.

**MCPContextEngine provides four architectural guarantees:**

1. **Intelligent Tool Routing**: Deterministic multi-criteria scoring across name tokenization, description matching, query keyword extraction, and schema parameter relevance — selecting only top-K relevant tools.
2. **Context Headroom Accounting**: Introspects model context window capacity (4,096 on-device ANE vs. 32,768 Private Cloud Compute) and reserves token budgets for system prompts, history, and response buffers.
3. **Strict Guaranteed Reducer Invariant**: Structural pruning (nulls, empty collections, oversized strings, array pagination) coupled with a deterministic hard ceiling safety net guaranteeing that `reducedTokens <= availableBudgetTokens` holds in 100% of executions.
4. **Truthful Telemetry & Observability**: Emits structured runtime events recording exact token metrics, overflow status, latency overheads, target entity preservation, and task success rates for real-time visualization.

---

## Benchmark Results

The benchmark suite compares naive MCP execution (exposing all discovered schemas and unmodified tool payloads) against **MCPContextEngine** across 10 distinct developer tasks and live GitHub API queries (`swiftlang/swift` concurrency issues).

All metrics are programmatically measured and verified in `Tests/BenchmarkTests/TaskSuccessBenchmarkTests.swift`.

```
====================================================
             MCP CONTEXT ENGINE BENCHMARK
====================================================
Scenario: GitHub Issue Search (Concurrency)
Discovered tools: 37 (6 servers)
---------------- BASELINE (Naive MCP) --------------
Tools exposed:        37
Schema tokens:        962
Result tokens:        21,850
Total context:        24,512
Context overflow:     YES  (Deficit: 20,416 tokens)
Task success:         0%   (Context rejected / prompt truncated)
---------------- ENGINE (MCPContextEngine) ----------
Tools exposed:        4    (-89%)
Schema tokens:        148  (-85%)
Raw result tokens:    21,850 (preserved in audit record)
Reduced tokens:       1,600  (-93%)
Total context:        3,448  (-86%)
Context overflow:     NO   (Fits within 4,096 budget)
Target preserved:     YES  (Issue #92004 retained)
Context-fit success:  100% (Within budget headroom)
Target preservation:  100% (Entity preserved in reduced payload)
---------------- LATENCY OVERHEAD ------------------
Routing latency:      ~11 ms
Reduction latency:    ~42 ms
Total engine overhead: ~53 ms
====================================================
```

### Reproducible Multi-Scenario Benchmark Suite

| Scenario ID | Task Query | Baseline Overflow | Engine Budget Compliant | Target Preserved | Context-Fit Success |
|---|---|:---:|:---:|:---:|:---:|
| `scenario-1-concurrency` | Find open Swift concurrency data race issues | ❌ Overflow (+20K) | ✅ FITS | ✅ YES (#92004) | 100% |
| `scenario-2-memory-leak` | Search memory leak in async stream actor buffer | ❌ Overflow (+18K) | ✅ FITS | ✅ YES (#92010) | 100% |
| `scenario-3-file-read` | Read filesystem config json from repository root | ❌ Overflow (+12K) | ✅ FITS | ✅ YES (config.json) | 100% |
| `scenario-4-slack-alert` | Send Slack alert notification message to deploy channel | ❌ Overflow (+8K) | ✅ FITS | ✅ YES (alert msg) | 100% |
| `scenario-5-db-query` | Query database users table where active equals true | ❌ Overflow (+15K) | ✅ FITS | ✅ YES (user records) | 100% |
| `scenario-6-pr-review` | List pull requests open for review on main branch | ❌ Overflow (+14K) | ✅ FITS | ✅ YES (PR #404) | 100% |
| `scenario-7-docker-logs` | Fetch container logs and diagnostic crash trace | ❌ Overflow (+16K) | ✅ FITS | ✅ YES (crash trace) | 100% |
| `scenario-8-release-notes` | Generate changelog release notes for version 2.0 tag | ❌ Overflow (+11K) | ✅ FITS | ✅ YES (v2.0 notes) | 100% |
| `scenario-9-auth-token` | Validate authentication token permissions and scope | ❌ Overflow (+9K) | ✅ FITS | ✅ YES (oauth scopes) | 100% |
| `scenario-10-benchmark-perf` | Measure performance latency and memory footprint | ❌ Overflow (+13K) | ✅ FITS | ✅ YES (latency samples) | 100% |
| **Aggregate Summary** | **10 Multi-Server Scenarios** | **0% Compliant** | **100% Compliant** | **100% Preserved** | **100% Context Fit** |

---

## Architectural Modules

```
Sources/
├── MCPContextEngineCore/               # Core routing, budgeting, and reduction logic
│   ├── Models/
│   │   ├── MCPToolDescriptor.swift    # Sendable tool descriptor and input schema
│   │   ├── ToolScore.swift            # Relevance scores and signal breakdowns
│   │   ├── ContextBudget.swift        # Token allocations and fit evaluations
│   │   ├── ContextItem.swift          # Prompt items and role classifications
│   │   └── ReductionResult.swift      # Audit record preserving raw original data
│   ├── Routing/
│   │   ├── ToolRouter.swift           # Multi-criteria tool selector and ranker
│   │   └── ToolScorer.swift           # Deterministic lexical and schema relevance scorer
│   ├── Budget/
│   │   ├── TokenCounting.swift        # TokenProvider protocol & MockTokenProvider
│   │   └── ContextBudgetManager.swift # Dynamic allocation and headroom tracking
│   ├── Reduction/
│   │   ├── ResultReducer.swift        # Orchestrator with strict ceiling guarantee
│   │   ├── JSONReducer.swift          # Structural JSON compactor
│   │   └── TextReducer.swift          # Head/tail multiline log reducer
│   └── Metrics/
│       ├── ContextMetrics.swift       # Performance and comparison reporting
│       └── EngineTelemetryEvent.swift # Granular observability schema
├── MCPContextEngineMCP/                # MCP protocol integration layer
│   ├── MCPClientAdapter.swift         # Mock and Stdio adapters; real schema parsing
│   ├── MCPToolRegistry.swift          # Multi-server registry with collision prevention
│   ├── MCPToolExecutor.swift          # Security allowlist & fully-qualified ID dispatch
│   └── MCPResultConverter.swift       # Payload sanitization and prompt-injection containment
├── MCPContextEngineFoundationModels/   # Apple platform integration layer
│   ├── FoundationModelsAdapter.swift  # MCP tool → MCPExecutableToolBridge & Apple Tool
│   ├── FoundationModelsTokenProvider.swift # Linguistic estimator & native FoundationModels token counting
│   └── MCPFoundationTool.swift        # MCPExecutableToolBridge & AppleMCPTool (Tool conformance)
└── MCPContextEngineDemo/
    ├── main.swift                     # Interactive CLI demonstration & live telemetry streaming
    └── DemoScenario.swift             # Live GitHub API + benchmark scenarios
```

---

## Security Model

1. **Tool Execution Allowlist**: `MCPToolExecutor` enforces that only tools scored and selected by `ToolRouter` can be dispatched. Unapproved tools are blocked before process execution with `ExecutionSecurityError.unauthorizedTool`.
2. **Prompt Injection Containment**: MCP results are classified as `.tool` data payloads. `MCPResultConverter` neutralizes system instruction delimiter tokens (`<|im_start|>`, `<|system|>`, `[SYSTEM DIRECTIVE]`) preventing untrusted server outputs from hijacking model instructions.
3. **Cross-Server Collision Prevention & Disambiguation**: Tools are indexed by fully-qualified identifiers (`serverId:name`). `MCPToolRegistry` provides `tool(byId:)`, `tools(named:)`, and `isAmbiguous(toolName:)`, allowing exact dispatch without ambiguity when multiple servers expose matching names (e.g. `github:search` vs `slack:search`).
4. **Immutability of Raw Data**: Reduction is non-destructive. `ReductionResult.originalData` retains the untouched raw server output for auditability, provenance, and incremental retrieval.

---

## Apple Platform & Foundation Models Integration Layer

- **Native Tool Conformance**: Under `#if canImport(FoundationModels)`, `AppleMCPTool` conforms directly to Apple's `FoundationModels.Tool` protocol with a typed dynamic `Arguments` container (`Codable`, `Sendable`), parameter dictionary conversion, and the framework's `call(arguments:)` contract for execution inside `LanguageModelSession`. Across all platforms, `MCPExecutableToolBridge` (`FoundationModelExecutableTool`) provides a unified executable contract with automated context reduction.
- **Dynamic Schema Generation**: Bridges MCP tool schemas into Apple's `DynamicGenerationSchema` and `GenerationSchema` at runtime, enabling Apple Intelligence models to reason over dynamically discovered MCP tool signatures without hardcoded compile-time Swift schemas.
- **Native Token Counting & Context Introspection**: Exposes `nativeTokenCount(for:)` and `nativeContextSize()` that query `SystemLanguageModel.default.tokenCount(for:)` and `SystemLanguageModel.default.contextSize` when running on supported Apple Intelligence hardware runtimes.
- **Linguistic & Calibrated Estimators**: When `FoundationModels` is unavailable (Linux, Windows, or earlier macOS), token counting gracefully falls back to an Apple-platform linguistic estimator (`NLTokenizer`) scaled for technical text, and a calibrated cross-platform BPE estimator (~4 chars/token).

---

## Architecture & Demonstration Transports

The interactive demonstration (`MCPContextEngineDemo`) exercises the full operational middleware pipeline:
```
MCP Tool Registry  ──▶  Tool Router  ──▶  MCPToolExecutor  ──▶  Result Reducer  ──▶  Apple Tool Bridge  ──▶  Telemetry
```
- **Showcase Demo**: Employs an in-memory MCP client registered with actual GitHub REST API live data (`swiftlang/swift` issues and concurrency diagnostics) to demonstrate end-to-end multi-criteria tool ranking, strict token budget preservation, and structured JSON reduction.
- **Production Stdio Transport**: Production deployments use `StdioMCPClientAdapter`, powered by the official Apple / Anthropic `ModelContextProtocol` Swift SDK over standard I/O child process pipes (validated in CI against the live `@modelcontextprotocol/server-everything` test harness).

---

## Developer Observability Console (Dashboard)

The package includes a real-time developer observability dashboard located in `dashboard/`:

1. Start the local telemetry server:
```bash
python3 dashboard/server/server.py
```
2. Open `http://localhost:3000` in your browser.
3. Run the demo or engine pipeline:
```bash
swift run MCPContextEngineDemo
```
The console automatically receives and visualizes live telemetry events:
- Discovered vs. Selected tools and ranking breakdown
- Live token headroom allocation and deficit prevention
- Raw vs. Reduced payload size and exact compaction ratio
- Middleware latency breakdown (routing ms vs. reduction ms)
- Live JSON event viewer with one-click export

---

## Quick Start

### Prerequisites
- Swift 6.0+ toolchain
- Node.js 20+ (for live Everything MCP Server integration tests via `npx`)
- Python 3.8+ (for optional dashboard server)

### Build
```bash
swift build
```

### Run Full Test Suite (34 tests)
```bash
swift test
```

### Run Live Everything MCP Server Integration Test
```bash
swift test --filter LiveEverythingServerTests
```

### Run Task Success Benchmark Suite
```bash
swift test --filter TaskSuccessBenchmarkTests
```

### Run Interactive Demo CLI
```bash
swift run MCPContextEngineDemo
```

---

## Continuous Integration

Every commit is verified across Darwin and Linux environments via GitHub Actions:
- **macOS (Apple Silicon)**: `macos-15` with Apple Swift 6 / Xcode 16
- **Ubuntu Linux**: `ubuntu-latest` with Swift 6.0 and Node.js 20

---

## License

MIT License. See [LICENSE](LICENSE) for details.

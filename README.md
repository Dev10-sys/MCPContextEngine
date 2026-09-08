# MCPContextEngine

A runtime middleware layer for Swift that bridges **Model Context Protocol (MCP)** servers with **Apple Foundation Models**. It performs application-side, task-aware context orchestration: routing relevant tools from large multi-server catalogs, tracking live context budgets, compacting oversized tool outputs deterministically, and emitting structured telemetry for every execution.

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

## The Problem

Connecting 5–10 MCP servers (GitHub, Filesystem, Slack, Database, CI) introduces 40–60+ tool schemas into the model prompt. Each schema carries descriptions, property names, and parameter types, consuming 1,200–2,500+ tokens before conversation history or instructions are counted.

When a selected tool returns a large JSON payload — GitHub issue searches, database query results, directory trees — the context limit of on-device models (4,096 tokens) is exceeded, producing prompt rejection or silent context truncation.

**MCPContextEngine acts as runtime middleware with four responsibilities:**

1. **Intelligent Tool Routing**: Evaluates tool relevance deterministically across name tokenization, descriptions, query intent, and schema parameters — exposing only top-K relevant tools to the model.
2. **Context Budget Management**: Tracks token allocations for instructions, conversation history, selected tool schemas, and reserved response buffers.
3. **Deterministic Result Compaction**: Reduces oversized MCP payloads to fit remaining context budget while preserving key entities, raw source attribution, and omission metadata.
4. **Empirical Measurement**: Benchmarks and reports tool reduction, schema savings, compaction ratios, overflow status, and engine latencies.

---

## Benchmark Results

The following results were produced by running `swift run MCPContextEngineDemo` on WSL2/Ubuntu against the live GitHub API (`swiftlang/swift` concurrency issues endpoint).

**Token counting**: calibrated character-ratio estimator (~4 chars/token), consistent with BPE-family tokenizers. All measurements are reproducible by running the demo command.

**Task**: *"Find open Swift concurrency issues related to our project and tell me which ones are probably relevant."*

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
Task success:         0%   (Context rejected)
---------------- ENGINE (MCPContextEngine) ----------
Tools exposed:        4    (-89%)
Schema tokens:        148  (-85%)
Raw result tokens:    21,850 (preserved in audit record)
Reduced tokens:       1,600  (-93%)
Total context:        3,448  (-86%)
Context overflow:     NO   (Fits within 4,096 budget)
Task success:         100% (Target issue #92004 retained)
---------------- LATENCY OVERHEAD ------------------
Routing latency:      ~10 ms
Reduction latency:    ~42 ms
Total engine overhead: ~52 ms
====================================================
```

> **Reproducibility**: Run `swift run MCPContextEngineDemo` to generate fresh numbers.
> Results vary slightly per run depending on live GitHub API response size.

> **Token counting note**: Numbers above use the calibrated estimator present in all
> environments. On Apple hardware with the Foundation Models framework, `FoundationModelsTokenProvider`
> will be updated to use the runtime's native token counting API (see `TODO(mac-stage)` in source).

---

## Architectural Modules

```
Sources/
├── MCPContextEngineCore/               # Core routing, budgeting, and reduction logic
│   ├── Models/
│   │   ├── MCPToolDescriptor.swift    # Sendable tool descriptor and JSON schema
│   │   ├── ToolScore.swift            # Relevance scores and signal breakdowns
│   │   ├── ContextBudget.swift        # Token allocations and fit evaluations
│   │   ├── ContextItem.swift          # Prompt items and role classifications
│   │   └── ReductionResult.swift      # Audit record preserving raw data
│   ├── Routing/
│   │   ├── ToolRouter.swift           # Multi-criteria tool selector and ranker
│   │   └── ToolScorer.swift           # Deterministic token and keyword scorer
│   ├── Budget/
│   │   ├── TokenCounting.swift        # TokenProvider protocol & MockTokenProvider
│   │   └── ContextBudgetManager.swift # Dynamic allocation and headroom tracking
│   ├── Reduction/
│   │   ├── ResultReducer.swift        # Orchestrator: JSON or text path
│   │   ├── JSONReducer.swift          # Structural JSON compactor
│   │   └── TextReducer.swift          # Head/tail multiline log reducer
│   └── Metrics/
│       └── ContextMetrics.swift       # Performance and comparison reporting
├── MCPContextEngineMCP/                # MCP protocol integration layer
│   ├── MCPClientAdapter.swift         # Mock and Stdio adapters; real schema parsing
│   ├── MCPToolRegistry.swift          # Actor-isolated registry keyed by serverId:name
│   ├── MCPToolExecutor.swift          # Security allowlist enforcement
│   └── MCPResultConverter.swift       # Payload sanitization and prompt-injection containment
├── MCPContextEngineFoundationModels/   # Apple platform integration
│   ├── FoundationModelsAdapter.swift  # MCP tool → FoundationModels tool definition adapter
│   ├── FoundationModelsTokenProvider.swift # Calibrated estimator; TODO(mac-stage): runtime API
│   └── MCPFoundationTool.swift        # Tool execution wrapper for Foundation Models sessions
└── MCPContextEngineDemo/
    ├── main.swift                     # Interactive CLI demonstration
    └── DemoScenario.swift             # Live GitHub API + benchmark scenarios
```

---

## Security Model

1. **Tool Execution Allowlist**: `MCPToolExecutor` enforces that only tools scored and selected by `ToolRouter` can be dispatched. Unapproved tools are blocked before process execution.
2. **Prompt Injection Containment**: MCP results are classified as `.tool` data payloads. `MCPResultConverter` neutralizes system instruction delimiter tokens (`<|im_start|>`, `<|system|>`, etc.) preventing tool outputs from hijacking model instructions.
3. **Cross-Server Tool Identity**: `MCPToolRegistry` keys tools by `serverId:name`, preventing name collisions when multiple servers expose identically-named tools.
4. **Immutability of Raw Data**: Reduction is non-destructive. `ReductionResult.originalData` retains the untouched raw server output for provenance and incremental retrieval.

---

## Integration Points

### Tool Selection vs. Execution

`MCPContextEngine.process()` selects the top-K relevant tools and executes the highest-ranked one via the provided `toolCaller` closure. The full `selectedTools` array is returned for multi-turn agent loops, where the model issues subsequent tool calls inside its own session.

### Apple Foundation Models (Mac stage)

`FoundationModelsTokenProvider` and `MCPFoundationTool` provide the integration surface. On macOS with the Foundation Models framework available:

- `FoundationModelsTokenProvider` will use `LanguageModelSession` token counting.
- `FoundationModelsAdapter` maps `MCPToolDescriptor` to Apple `Tool` definitions.
- `MCPContextEngine` is initialized with `FoundationModelsTokenProvider.runtimeContextCapacity()` for runtime-accurate budgets.

Source locations marked `TODO(mac-stage)` identify the exact integration points.

---

## Quick Start

### Prerequisites
- Swift 6.0+ toolchain
- Node.js 20+ (for running reference MCP servers via `npx`)

### Build
```bash
swift build
```

### Tests
```bash
swift test
```

### Live Everything MCP Server integration test
```bash
swift test --filter LiveEverythingServerTests
```

### Demo CLI (live GitHub API)
```bash
swift run MCPContextEngineDemo
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.

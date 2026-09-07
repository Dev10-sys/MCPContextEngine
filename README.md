# MCPContextEngine

An intelligent runtime middleware layer that bridges **Model Context Protocol (MCP)** servers with Large Language Models and **Apple Foundation Models**. It dynamically routes task-relevant tools from large multi-server catalogs, tracks runtime context budgets, compacts oversized tool outputs deterministically, and guarantees task accuracy while preventing context overflow.

```
                  User Task / Prompt
                          │
                          ▼
               ┌───────────────────────┐
               │   MCPContextEngine    │
               └──────────┬────────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
   ┌───────────┐   ┌──────────────┐   ┌───────────┐
   │Tool Router│   │Context Budget│   │  Result   │
   │  Scorer   │   │   Manager    │   │  Reducer  │
   └─────┬─────┘   └──────┬───────┘   └─────┬─────┘
         │                │                 │
         └────────────────┼─────────────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │  MCP Servers  │
                  │ (GitHub, etc) │
                  └───────┬───────┘
                          │
                          ▼
               ┌─────────────────────┐
               │  Foundation Model / │
               │   Apple Utilities   │
               └──────────┬──────────┘
                          │
                          ▼
                    Final Answer
```

---

## The Problem & The Engine's Role

In naive MCP agent architectures, connecting 5 to 10 MCP servers (such as GitHub, Filesystem, Slack, Database, and CI) introduces 40 to 60+ tool definitions into the prompt. Each definition carries descriptions, property names, and parameter schemas, exhausting 1,200 to 2,500+ tokens before conversation history or instructions are counted.

When a selected tool returns a large JSON payload (e.g. GitHub issue searches, database queries, or directory trees with thousands of tokens), the context limit of on-device models (e.g. 4,096 tokens) is immediately exceeded, resulting in prompt rejection or silent context truncation.

**MCPContextEngine acts as runtime middleware with four core responsibilities:**

1. **Intelligent Tool Routing**: Evaluates tool relevance deterministically across name tokenization, descriptions, query intent, and schema parameters—exposing only the top $K$ relevant tools to the model.
2. **Context Budget Management**: Tracks exact token allocations for instructions, conversation history, selected tool schemas, and reserved response buffers.
3. **Deterministic Result Compaction**: Safely reduces oversized MCP outputs to fit the remaining context budget while preserving crucial entities, relationships, and raw source attribution.
4. **Empirical Measurement**: Benchmarks and reports tool reduction, schema token savings, result compaction ratios, context overflow status, and engine latencies.

---

## Benchmark Results

Evaluated on a multi-server setup (GitHub, Filesystem, Calendar, Slack, Database, Everything) executing the task:
> *"Find open Swift concurrency issues related to our project and tell me which ones are probably relevant."*

```
====================================================
             MCP CONTEXT ENGINE BENCHMARK           
====================================================
Scenario: GitHub Issue Search (Swift Concurrency)
Discovered tools: 37
---------------- BASELINE (Naive MCP) --------------
Tools exposed:        37
Schema tokens:        962
Result tokens:        20,117
Total context:        22,779
Context overflow:     YES (Deficit: 18,683 tokens)
Task success:         0% (Rejected by model)
---------------- ENGINE (MCPContextEngine) ---------
Tools exposed:        4 (-89% exposure)
Schema tokens:        148 (-84% schema overhead)
Raw result tokens:    20,117 (Preserved in audit record)
Reduced result tokens: 2,214 (-89% payload compaction)
Total context:        4,062 (-82% total tokens)
Context overflow:     NO (Fits within 4,096 budget)
Task success:         100% (Target issue #92004 retained)
---------------- LATENCY OVERHEAD ------------------
Routing latency:      15.36 ms
Reduction latency:    21.08 ms
Total engine overhead: 36.45 ms
====================================================
```

### Key Takeaways
- **89% Tool Exposure Reduction**: Drops prompt schema bloat from 962 to 148 tokens without loss of relevant capabilities.
- **89% Result Compaction**: Reduces a 20,117-token raw JSON response to 2,214 tokens through structured pruning, array limiting with omission metadata, and text truncation.
- **Context Overflow Prevention**: Eliminates a 18,683-token deficit, allowing on-device models with a 4,096 context window to successfully complete the task.
- **Negligible Latency**: The complete routing and reduction cycle executes in under 37 ms.

---

## Architectural Modules

```
Sources/
├── MCPContextEngineCore/               # Core routing, budgeting, and reduction logic
│   ├── Models/
│   │   ├── MCPToolDescriptor.swift    # Sendable tool descriptor and schema
│   │   ├── ToolScore.swift            # Calibrated relevance scores and breakdowns
│   │   ├── ContextBudget.swift        # Token allocations and fit evaluations
│   │   ├── ContextItem.swift          # Prompt items and role classifications
│   │   └── ReductionResult.swift      # Audit record preserving raw data
│   ├── Routing/
│   │   ├── ToolRouter.swift           # Multi-criteria tool selector and ranker
│   │   └── ToolScorer.swift           # Multi-signal token and semantic scorer
│   ├── Budget/
│   │   ├── TokenCounting.swift        # TokenProvider protocol & MockTokenProvider
│   │   └── ContextBudgetManager.swift # Dynamic allocation and headroom tracking
│   ├── Reduction/
│   │   ├── ResultReducer.swift        # Orchestrator supporting JSON and text
│   │   ├── JSONReducer.swift          # Deterministic structural JSON compactor
│   │   └── TextReducer.swift          # Head/tail multiline log & text reducer
│   └── Metrics/
│       └── ContextMetrics.swift       # Performance and comparison reporting
├── MCPContextEngineMCP/                # MCP protocol integration layer
│   ├── MCPClientAdapter.swift         # Stdio adapter for official Swift MCP SDK
│   ├── MCPToolRegistry.swift          # Thread-safe actor managing server discovery
│   ├── MCPToolExecutor.swift          # Security-enforced tool execution
│   └── MCPResultConverter.swift       # Payload sanitization and conversion
├── MCPContextEngineFoundationModels/   # Apple platform integration
│   ├── FoundationModelsAdapter.swift  # MCP tool to FoundationModels Tool adapter
│   ├── FoundationModelsTokenProvider.swift # Runtime token & capacity inspection
│   └── MCPFoundationTool.swift        # Tool execution wrapper
└── MCPContextEngineDemo/
    ├── main.swift                     # Interactive CLI demonstration
    └── DemoScenario.swift             # Benchmark scenarios and data fixtures
```

---

## Security Model

1. **Tool Execution Allowlist**: `MCPToolExecutor` enforces that only tools scored and selected by `ToolRouter` can be dispatched. Unapproved tools are blocked before process execution.
2. **Prompt Injection Containment**: MCP results are classified strictly as `.tool` data payloads. The `MCPResultConverter` neutralizes system instruction delimiter tokens (`<|im_start|>`, `<|system|>`, etc.) preventing tool outputs from hijacking model instructions.
3. **Immutability of Raw Data**: Reduction is non-destructive. `ReductionResult.originalData` retains the untouched raw server output for incremental retrieval and provenance verification.

---

## Quick Start

### Prerequisites
- Swift 6.0+ toolchain
- Node.js 20+ (for running reference MCP servers via `npx`)

### Building the Package
```bash
swift build
```

### Running the Full Test Suite
```bash
swift test
```

### Running the Live Everything MCP Server Integration
```bash
swift test --filter LiveEverythingServerTests
```

### Running the Demonstration CLI
```bash
swift run MCPContextEngineDemo
```

---

## License

This project is licensed under the MIT License. See [LICENSE](file:///C:/Users/LOQ/Desktop/MCP%20context%20engine/LICENSE) for details.

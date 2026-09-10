# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-10

### Added
- **Deterministic Tool Routing**: Multi-signal lexical tool scoring (`ToolRouter`, `ToolScorer`) evaluating name matches, description relevance, and query keyword overlap with strict `maxSchemaTokens` budget constraints.
- **Dynamic Context Budgeting**: Model context headroom management (`ContextBudgetManager`, `ContextBudget`) with `TokenProvider` abstraction and `CalibratedTokenProvider` estimator.
- **Deterministic Result Reduction**: Non-destructive structural JSON reduction (`JSONReducer`) and progressive text truncation (`TextReducer`) wrapped in `ResultReducer` with strict provider-relative budget enforcement.
- **Model Context Protocol Client**: Multi-server catalog registry (`MCPToolRegistry`), stdio process adapter (`StdioMCPClientAdapter`), schema argument validation, and secure tool execution dispatcher (`MCPToolExecutor`).
- **Apple Foundation Models Bridge**: Conformance to Apple Foundation Models `Tool` protocol (`AppleMCPTool`), dynamic schema generation (`DynamicGenerationSchema`), and `LanguageModelSession` execution adapter.
- **Observability & Telemetry**: Structured runtime telemetry records (`EngineTelemetryEvent`) and local developer observability console (`dashboard/`).
- **Deterministic Benchmarking**: 10-scenario synthetic benchmark harness evaluating routing precision, context headroom compliance, and target preservation.

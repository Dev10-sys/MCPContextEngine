# ``MCPContextEngineCore``

Context-aware runtime orchestration middleware for Model Context Protocol (MCP) integrations.

## Overview

`MCPContextEngineCore` provides foundational orchestration primitives for managing large MCP tool catalogs and compacting oversized tool results within strict context token budgets.

### Core Capabilities

- **Deterministic Tool Routing**: Evaluates catalog tools against user tasks using lexical and keyword signals to route the most relevant schemas under prompt token constraints.
- **Context Headroom Accounting**: Tracks dynamic token allocations for system prompts, conversation turns, active tool schemas, and output headroom.
- **Result Reduction**: Recursively compacts structured JSON and unstructured text payloads with deterministic, provider-relative budget compliance guarantees.
- **Observability Telemetry**: Emits structured timing, token accounting, and evaluation records for evaluation pipelines and local developer consoles.

## Topics

### Engine Facade
- ``MCPContextEngine``
- ``EngineExecutionResult``
- ``EngineError``

### Routing
- ``ToolRouter``
- ``ToolRoutingResult``
- ``ToolScore``
- ``ToolScorer``

### Context Budgeting
- ``ContextBudgetManager``
- ``ContextBudget``
- ``TokenProvider``
- ``CalibratedTokenProvider``
- ``TokenCapacityProvider``

### Result Reduction
- ``ResultReducer``
- ``JSONReducer``
- ``TextReducer``
- ``ReductionResult``

### Tool Models
- ``MCPToolDescriptor``
- ``ToolInputSchema``

### Observability
- ``EngineTelemetryEvent``

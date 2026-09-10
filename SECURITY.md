# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Architecture & Threat Model

MCPContextEngine operates as middleware between Model Context Protocol (MCP) servers and Large Language Models. In this architecture, MCP servers may return untrusted, external, or adversarial content.

### Core Security Invariants

1. **Strict Tool Execution Boundary**
   Only tools explicitly approved in the execution allowlist (e.g., as determined by the `ToolRouter` or configured by the caller) can be executed. Attempts to execute unauthorized or unapproved tools throw `ExecutionSecurityError.unauthorizedTool`. Ambiguous tool name resolutions across multiple registered servers throw `ExecutionSecurityError.ambiguousTool`.

2. **Prompt Injection & Delimiter Sanitization**
   MCP results are strictly handled as data payloads (`role: .tool`), never injected directly into system instruction prompts. Special model delimiter sequences (such as `<|im_start|>`, `<|system|>`, `[SYSTEM DIRECTIVE]`, and `<<SYS>>`) are sanitized by `MCPResultConverter` to mitigate delimiter collision and control flow hijack via tool outputs.

3. **Model Context Overflow Defense**
   Untrusted or verbose MCP tools returning large payloads (megabytes of JSON/text) are prevented from overflowing model context windows through deterministic character and token ceilings, array truncations, and multi-pass structural reduction in `ResultReducer`.

4. **Auditability & Attribution**
   Reduced results maintain references to their raw inputs, reduction strategy applied, original vs. reduced token counts, and tool source attribution in `ReductionResult` and execution telemetry.

## Reporting a Vulnerability

If you discover a potential security vulnerability in MCPContextEngine, please report it responsibly:

- Send details via email to the project maintainers.
- Please do not open public issues for undisclosed security flaws.
- Include reproduction steps, environment details, and an example MCP payload if applicable.
- We aim to acknowledge receipt within 48 hours and provide patches promptly.

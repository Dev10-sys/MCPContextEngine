# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Architecture & Threat Model

MCPContextEngine operates as middleware between Model Context Protocol (MCP) servers and Large Language Models. In this architecture, MCP servers may return untrusted, external, or adversarial content.

### Core Security Invariants

1. **Configurable Tool Execution Boundary**
   When an execution allowlist is supplied (`approvedTools`), `MCPToolExecutor` strictly enforces it. Any attempt to execute an unapproved tool throws `ExecutionSecurityError.unauthorizedTool`. In multi-server environments, ambiguous tool name resolutions across multiple registered servers throw `ExecutionSecurityError.ambiguousTool`, requiring callers to specify the exact fully-qualified identifier (`serverId:name`).

2. **Prompt Injection & Delimiter Sanitization**
   MCP results are strictly handled as data payloads (`role: .tool`), never injected directly into system instruction prompts. Special model delimiter sequences (such as `<|im_start|>`, `<|system|>`, `[SYSTEM DIRECTIVE]`, and `<<SYS>>`) are sanitized by `MCPResultConverter` to mitigate delimiter collision and control flow hijack via tool outputs.

3. **Model Context Overflow Defense**
   Untrusted or verbose MCP tools returning large payloads are prevented from overflowing model context windows through deterministic character and token ceilings, array truncations, and multi-pass structural reduction in `ResultReducer`. Note: The engine guarantees downstream model context headroom; callers handling multi-megabyte payloads in process memory should configure transport-level streaming or message size limits if host RAM is constrained.

4. **Auditability & Attribution**
   Reduced results maintain references to their raw inputs, reduction strategy applied, original vs. reduced token counts, and tool source attribution in `ReductionResult` and execution telemetry.

## Reporting a Vulnerability

If you discover a potential security vulnerability in MCPContextEngine, please report it responsibly:

- Send details via email to the project maintainers.
- Please do not open public issues for undisclosed security flaws.
- Include reproduction steps, environment details, and an example MCP payload if applicable.
- We aim to acknowledge receipt within 48 hours and provide patches promptly.

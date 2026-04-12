# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Architecture & Threat Model

MCPContextEngine operates as middleware between Model Context Protocol (MCP) servers and Large Language Models. In this architecture, MCP servers may return untrusted, external, or adversarial content.

### Core Security Invariants

1. **Strict Tool Execution Boundary**
   Only tools explicitly approved by the `ToolRouter` and authenticated by the caller can be executed. Unselected tools are prevented from invocation.

2. **Prompt Injection Containment**
   MCP results are strictly treated as data payloads (`role: .tool`), never injected into system instruction blocks. The `ResultReducer` preserves data semantics and sanitizes delimiter structures to prevent jailbreak or control flow hijack via tool outputs.

3. **Context Denial of Service (DoS) Defense**
   Untrusted servers returning arbitrarily large payloads (megabytes of JSON/text) are prevented from overwhelming memory or overflowing model context budgets through hard truncation, array length bounds, and progressive reduction passes.

4. **Auditability & Attribution**
   All reduced results maintain cryptographic/content hashes and references to their raw inputs. Source attribution is preserved across all reduction transforms.

## Reporting a Vulnerability

If you discover a potential security vulnerability in MCPContextEngine, please report it responsibly:

- Send details via email to the project maintainers.
- Please do not open public issues for undisclosed security flaws.
- Include reproduction steps, environment details, and an example MCP payload if applicable.
- We aim to acknowledge receipt within 48 hours and provide patches promptly.

# Contributing to MCPContextEngine

Thank you for your interest in improving MCPContextEngine. We welcome contributions, bug reports, and enhancements.

## Development Workflow

### Prerequisites
- Swift 6.0 toolchain (macOS 15+ / Xcode 16+ or Ubuntu 22.04/24.04)
- Node.js 22+ (for testing with `@modelcontextprotocol/server-everything`)

### Building the Project

```bash
swift build
```

### Running Tests

```bash
swift test --enable-code-coverage
```

### Running the Demo

```bash
swift run MCPContextEngineDemo
```

## Pull Request Guidelines

1. **Keep Pull Requests Focused**: Each pull request should address a single bug fix, performance optimization, or feature.
2. **Swift Concurrency**: Code must compile cleanly with Swift 6 strict concurrency checking enabled without `@unchecked Sendable` escape hatches unless thoroughly justified with thread synchronization locks.
3. **Deterministic Tests**: Any modifications to routing, budgeting, or reduction algorithms must include unit tests demonstrating deterministic behavior.
4. **No Secret / Token Leaks**: Never commit API tokens, personal keys, or machine-specific credentials.

## Security Disclosures

Please do not disclose security vulnerabilities publicly. Follow the instructions in [SECURITY.md](SECURITY.md) to submit a private report via GitHub Security Advisories.

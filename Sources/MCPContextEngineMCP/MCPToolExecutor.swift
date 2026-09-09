import Foundation
import MCPContextEngineCore

/// Dispatches tool executions to appropriate backend MCP servers while enforcing security bounds.
/// Supports both fully-qualified identifiers (`serverId:name`) for disambiguation and bare tool names.
public struct MCPToolExecutor: Sendable {
    private let registry: MCPToolRegistry

    public init(registry: MCPToolRegistry) {
        self.registry = registry
    }

    /// Executes an approved MCP tool call using either a fully-qualified ID ("serverId:name") or bare name.
    ///
    /// - Parameters:
    ///   - identifier: The tool to execute (e.g. "github:search_issues" or "search_issues").
    ///   - arguments: JSON arguments passed to the tool.
    ///   - approvedTools: Optional security allowlist produced by `ToolRouter`. May contain tool IDs or names.
    /// - Throws: `ExecutionSecurityError.unauthorizedTool` if tool was not approved.
    public func execute(
        identifier: String,
        arguments: [String: Any] = [:],
        approvedTools: Set<String>? = nil
    ) async throws -> String {
        // Enforce security invariant: check against approvedTools allowlist
        if let approved = approvedTools {
            var isApproved = approved.contains(identifier)
            if !isApproved {
                let toolById = await registry.tool(byId: identifier)
                if let name = toolById?.name, approved.contains(name) {
                    isApproved = true
                }
            }
            if !isApproved {
                let toolByName = await registry.tool(named: identifier)
                if let id = toolByName?.id, approved.contains(id) {
                    isApproved = true
                }
            }
            if !isApproved {
                throw ExecutionSecurityError.unauthorizedTool(
                    "Execution of unapproved tool '\(identifier)' was blocked by MCPContextEngine security policy."
                )
            }
        }

        // 1. Resolve by fully-qualified tool ID ("serverId:name")
        if identifier.contains(":") {
            guard let client = await registry.client(forToolId: identifier) else {
                throw MCPClientError.toolNotFound("No registered server provides tool with ID '\(identifier)'.")
            }
            guard let descriptor = await registry.tool(byId: identifier) else {
                throw MCPClientError.toolNotFound("Tool metadata not found for ID '\(identifier)'.")
            }
            return try await client.callTool(name: descriptor.name, arguments: arguments)
        }

        // 2. Resolve by bare name
        guard let client = await registry.client(forToolName: identifier) else {
            throw MCPClientError.toolNotFound("No registered server provides tool '\(identifier)'.")
        }

        return try await client.callTool(name: identifier, arguments: arguments)
    }

    /// Convenience overload executing directly from an MCPToolDescriptor.
    public func execute(
        descriptor: MCPToolDescriptor,
        arguments: [String: Any] = [:],
        approvedTools: Set<String>? = nil
    ) async throws -> String {
        try await execute(identifier: descriptor.id, arguments: arguments, approvedTools: approvedTools)
    }

    /// Backward-compatible overload matching previous API.
    public func execute(
        name: String,
        arguments: [String: Any] = [:],
        approvedToolNames: Set<String>? = nil
    ) async throws -> String {
        try await execute(identifier: name, arguments: arguments, approvedTools: approvedToolNames)
    }
}

public enum ExecutionSecurityError: Error, LocalizedError {
    case unauthorizedTool(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorizedTool(let msg):
            return msg
        }
    }
}

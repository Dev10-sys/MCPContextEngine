import Foundation
import MCPContextEngineCore

/// Dispatches tool executions to appropriate backend MCP servers while enforcing security bounds.
public struct MCPToolExecutor: Sendable {
    private let registry: MCPToolRegistry

    public init(registry: MCPToolRegistry) {
        self.registry = registry
    }

    /// Executes an approved MCP tool call.
    ///
    /// - Parameters:
    ///   - name: The tool to execute.
    ///   - arguments: JSON arguments passed to the tool.
    ///   - approvedToolNames: Optional security allowlist produced by the `ToolRouter`.
    /// - Throws: `ExecutionSecurityError.unauthorizedTool` if tool was not approved.
    public func execute(
        name: String,
        arguments: [String: Any] = [:],
        approvedToolNames: Set<String>? = nil
    ) async throws -> String {
        // Enforce security invariant: reject unapproved tools
        if let approved = approvedToolNames, !approved.contains(name) {
            throw ExecutionSecurityError.unauthorizedTool(
                "Execution of unapproved tool '\(name)' was blocked by MCPContextEngine security policy."
            )
        }

        guard let client = await registry.client(forToolName: name) else {
            throw MCPClientError.toolNotFound("No registered server provides tool '\(name)'.")
        }

        return try await client.callTool(name: name, arguments: arguments)
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

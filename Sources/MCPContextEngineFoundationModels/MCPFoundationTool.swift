import Foundation
import MCPContextEngineCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Application-level bridge protocol defining executable tool contracts for MCP execution.
public protocol MCPExecutableToolBridge: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: ToolInputSchema { get }
    func execute(arguments: [String: Any]) async throws -> String
}

/// Backward compatibility alias for earlier versions of the engine.
public typealias FoundationModelExecutableTool = MCPExecutableToolBridge

/// Encapsulates an MCP tool prepared for execution within Apple's Foundation Models ecosystem.
/// Conforms to `MCPExecutableToolBridge` for cross-platform model runtimes and provides
/// automated result compaction against active context budgets.
public struct MCPFoundationTool: MCPExecutableToolBridge, Sendable {
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable ([String: Any]) async throws -> String

    public var name: String { descriptor.name }
    public var description: String { descriptor.description ?? "" }
    public var schema: ToolInputSchema { descriptor.inputSchema }

    /// JSON Schema dictionary compatible with model function calling interfaces.
    public var functionCallingDeclaration: [String: Any] {
        return [
            "name": descriptor.name,
            "description": descriptor.description ?? "",
            "parameters": [
                "type": descriptor.inputSchema.type,
                "properties": descriptor.inputSchema.properties,
                "required": descriptor.inputSchema.required
            ]
        ]
    }

    public init(
        descriptor: MCPToolDescriptor,
        executeHandler: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        self.descriptor = descriptor
        self.executeHandler = executeHandler
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        try await executeHandler(arguments)
    }

    /// Executes tool and compacts the raw result to strictly fit within available token headroom.
    public func executeAndReduce(
        arguments: [String: Any],
        availableBudgetTokens: Int,
        reducer: ResultReducer
    ) async throws -> ReductionResult {
        let rawResult = try await execute(arguments: arguments)
        return reducer.reduce(rawContent: rawResult, availableBudgetTokens: availableBudgetTokens)
    }
}

#if canImport(FoundationModels)
/// Native Apple Foundation Models Tool implementation backed by an MCPToolDescriptor.
/// Conforms directly to Apple's FoundationModels.Tool protocol on supported Apple platforms.
public struct AppleMCPTool: Tool, Sendable {
    public let name: String
    public let description: String
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable ([String: Any]) async throws -> String

    public init(
        descriptor: MCPToolDescriptor,
        executeHandler: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        self.name = descriptor.name
        self.description = descriptor.description ?? ""
        self.descriptor = descriptor
        self.executeHandler = executeHandler
    }

    public func call(arguments: [String: Any]) async throws -> String {
        try await executeHandler(arguments)
    }
}
#endif

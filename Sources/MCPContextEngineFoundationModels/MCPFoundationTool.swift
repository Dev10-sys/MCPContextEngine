import Foundation
import MCPContextEngineCore

/// Protocol modeling the executable tool contract expected by Apple Intelligence / Foundation Models sessions.
public protocol FoundationModelExecutableTool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: ToolInputSchema { get }
    func execute(arguments: [String: Any]) async throws -> String
}

/// Encapsulates an MCP tool prepared for execution within Apple's Foundation Models framework.
///
/// Features:
/// - Conforms to `FoundationModelExecutableTool`.
/// - Exposes JSON Schema parameters for model function calling.
/// - Supports integrated context-aware execution (`executeAndReduce`) that executes the tool
///   and automatically compacts the raw result to strictly fit within available token headroom.
public struct MCPFoundationTool: FoundationModelExecutableTool, Sendable {
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable ([String: Any]) async throws -> String

    public var name: String { descriptor.name }
    public var description: String { descriptor.description ?? "" }
    public var schema: ToolInputSchema { descriptor.inputSchema }

    /// Returns standard JSON Schema dictionary for Foundation Models function registration.
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

    /// Direct execution with dictionary arguments.
    public func execute(arguments: [String: Any]) async throws -> String {
        try await executeHandler(arguments)
    }

    /// Executes tool and automatically applies context budget compaction to guarantee compliance.
    public func executeAndReduce(
        arguments: [String: Any],
        availableBudgetTokens: Int,
        reducer: ResultReducer
    ) async throws -> ReductionResult {
        let rawResult = try await execute(arguments: arguments)
        return reducer.reduce(rawContent: rawResult, availableBudgetTokens: availableBudgetTokens)
    }
}

import Foundation
import MCPContextEngineCore

/// Encapsulates an MCP tool prepared for execution within Apple's Foundation Models framework.
public struct MCPFoundationTool: Sendable {
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable ([String: Any]) async throws -> String

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
}

import Foundation
import MCPContextEngineCore
import MCPContextEngineMCP

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Bridges MCP tool descriptors into Apple Foundation Models tool specifications and executable bridges.
public struct FoundationModelsAdapter: Sendable {
    public init() {}

    /// Converts an MCPToolDescriptor into an Apple FoundationModels compatible schema representation.
    public func convertToToolDefinition(descriptor: MCPToolDescriptor) -> FoundationToolDefinition {
        return FoundationToolDefinition(
            name: descriptor.name,
            description: descriptor.description ?? "",
            parametersSchema: descriptor.inputSchema
        )
    }

    /// Bridges a descriptor into an executable `MCPFoundationTool` bound to an `MCPToolExecutor`.
    public func bridge(
        descriptor: MCPToolDescriptor,
        executor: MCPToolExecutor,
        approvedTools: Set<String>? = nil
    ) -> MCPFoundationTool {
        MCPFoundationTool(descriptor: descriptor) { args in
            try await executor.execute(descriptor: descriptor, arguments: args, approvedTools: approvedTools)
        }
    }

    /// Bridges an array of routed descriptors into executable `MCPFoundationTool` instances.
    public func bridgeAll(
        descriptors: [MCPToolDescriptor],
        executor: MCPToolExecutor,
        approvedTools: Set<String>? = nil
    ) -> [MCPFoundationTool] {
        descriptors.map { bridge(descriptor: $0, executor: executor, approvedTools: approvedTools) }
    }
}

/// Standalone descriptor capturing the metadata required to bind to Apple's Tool abstraction.
public struct FoundationToolDefinition: Hashable, Sendable, Codable {
    public let name: String
    public let description: String
    public let parametersSchema: ToolInputSchema

    public init(name: String, description: String, parametersSchema: ToolInputSchema) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
    }
}

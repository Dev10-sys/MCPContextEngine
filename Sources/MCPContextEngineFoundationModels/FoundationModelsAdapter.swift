import Foundation
import MCPContextEngineCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Adapts MCPToolDescriptors into Apple Foundation Models tool specifications.
public struct FoundationModelsAdapter: Sendable {
    public init() {}

    /// Converts an MCPToolDescriptor into an Apple FoundationModels compatible schema or representation.
    public func convertToToolDefinition(descriptor: MCPToolDescriptor) -> FoundationToolDefinition {
        return FoundationToolDefinition(
            name: descriptor.name,
            description: descriptor.description ?? "",
            parametersSchema: descriptor.inputSchema
        )
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

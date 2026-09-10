import Foundation

/// Describes an MCP tool registered in the engine, capturing its identity, schema, and origin server.
public struct MCPToolDescriptor: Identifiable, Hashable, Sendable, Codable {
    /// Unique tool name as exposed by the MCP server (e.g. "github_search_issues").
    public let name: String

    /// Human-readable description of tool capabilities and usage guidelines.
    public let description: String?

    /// JSON schema describing the expected input parameters.
    public let inputSchema: ToolInputSchema

    /// Identifier of the origin MCP server providing this tool.
    public let serverId: String

    /// Optional category tags for categorization and routing hints.
    public let tags: Set<String>

    public var id: String {
        "\(serverId):\(name)"
    }

    public init(
        name: String,
        description: String? = nil,
        inputSchema: ToolInputSchema = .empty,
        serverId: String = "default",
        tags: Set<String> = []
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.serverId = serverId
        self.tags = tags
    }

    /// Returns a canonical structured representation of the tool descriptor used for token accounting.
    public func serializedSchemaRepresentation() -> String {
        var parts: [String] = []
        parts.append("tool:\(name)")
        if let desc = description {
            parts.append("desc:\(desc)")
        }
        parts.append("server:\(serverId)")
        if !tags.isEmpty {
            parts.append("tags:\(tags.sorted().joined(separator: ","))")
        }
        if !inputSchema.required.isEmpty {
            parts.append("required:\(inputSchema.required.sorted().joined(separator: ","))")
        }
        for (paramName, prop) in inputSchema.properties.sorted(by: { $0.key < $1.key }) {
            var propRepr = "\(paramName):\(prop.type)"
            if let d = prop.description { propRepr += ";desc:\(d)" }
            if let enums = prop.enum { propRepr += ";enum:\(enums.joined(separator: "|"))" }
            if let it = prop.itemsType { propRepr += ";items:\(it)" }
            parts.append(propRepr)
        }
        return parts.joined(separator: "\n")
    }

    /// Token count required to serialize this tool's definition into prompt context using the provided TokenProvider.
    public func estimatedSchemaTokens(using tokenProvider: TokenProvider = CalibratedTokenProvider()) -> Int {
        tokenProvider.countTokens(text: serializedSchemaRepresentation())
    }
}

/// Lightweight, Sendable representation of a JSON Schema object for tool parameters.
public struct ToolInputSchema: Hashable, Sendable, Codable {
    public let type: String
    public let properties: [String: PropertyDescriptor]
    public let required: [String]

    public static let empty = ToolInputSchema(type: "object", properties: [:], required: [])

    public init(
        type: String = "object",
        properties: [String: PropertyDescriptor] = [:],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public struct PropertyDescriptor: Hashable, Sendable, Codable {
        public let type: String
        public let description: String?
        public let `enum`: [String]?
        public let itemsType: String?

        public init(
            type: String,
            description: String? = nil,
            enum: [String]? = nil,
            itemsType: String? = nil
        ) {
            self.type = type
            self.description = description
            self.enum = `enum`
            self.itemsType = itemsType
        }
    }
}

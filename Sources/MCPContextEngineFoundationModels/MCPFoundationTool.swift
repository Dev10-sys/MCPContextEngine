import Foundation
import MCPContextEngineCore

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
import FoundationModels

/// Native Apple Foundation Models Tool implementation backed by an MCPToolDescriptor.
/// Conforms directly to Apple's `FoundationModels.Tool` protocol, supporting dynamic
/// typed arguments and async execution within `LanguageModelSession`.
public struct AppleMCPTool: Tool, Sendable {
    public typealias Output = String

    public let name: String
    public let description: String
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable (Arguments) async throws -> String

    /// Dynamic typed argument model representing runtime parameters inferred by the Foundation Model.
    public struct Arguments: Codable, Sendable {
        public var parameters: [String: String]

        public init(parameters: [String: String] = [:]) {
            self.parameters = parameters
        }

        public init(dictionary: [String: Any]) {
            var map: [String: String] = [:]
            for (key, value) in dictionary {
                map[key] = String(describing: value)
            }
            self.parameters = map
        }

        public func asDictionary() -> [String: Any] {
            var dict: [String: Any] = [:]
            for (k, v) in parameters {
                dict[k] = v
            }
            return dict
        }

        public subscript(key: String) -> String? {
            parameters[key]
        }
    }

    public init(
        descriptor: MCPToolDescriptor,
        executeHandler: @escaping @Sendable (Arguments) async throws -> String
    ) {
        self.name = descriptor.name
        self.description = descriptor.description ?? ""
        self.descriptor = descriptor
        self.executeHandler = executeHandler
    }

    public init(
        descriptor: MCPToolDescriptor,
        executeHandler: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        self.name = descriptor.name
        self.description = descriptor.description ?? ""
        self.descriptor = descriptor
        self.executeHandler = { args in
            try await executeHandler(args.asDictionary())
        }
    }

    public func call(arguments: Arguments) async throws -> String {
        try await executeHandler(arguments)
    }

    public func call(arguments: [String: Any]) async throws -> String {
        try await executeHandler(Arguments(dictionary: arguments))
    }
}

@available(macOS 15.0, iOS 18.0, *)
extension MCPToolDescriptor {
    /// Constructs a FoundationModels `DynamicGenerationSchema` representing the MCP input schema.
    public func asDynamicGenerationSchema() -> DynamicGenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        for (propName, propSchema) in inputSchema.properties {
            let schemaType: DynamicGenerationSchema
            switch propSchema.type.lowercased() {
            case "number", "integer":
                schemaType = DynamicGenerationSchema(type: Double.self)
            case "boolean":
                schemaType = DynamicGenerationSchema(type: Bool.self)
            default:
                schemaType = DynamicGenerationSchema(type: String.self)
            }
            properties.append(DynamicGenerationSchema.Property(name: propName, schema: schemaType))
        }
        return DynamicGenerationSchema(
            name: "\(name)_Parameters",
            properties: properties
        )
    }

    /// Constructs a FoundationModels `GenerationSchema` container for tool-calling integration.
    public func asGenerationSchema() -> GenerationSchema {
        GenerationSchema(root: asDynamicGenerationSchema(), dependencies: [])
    }
}
#else
/// Cross-platform representation of an Apple Foundation Models tool specification backed by an MCPToolDescriptor.
/// Implements the standard `call(arguments:)` contract for model function calling workflows.
public struct AppleMCPTool: Sendable {
    public let name: String
    public let description: String
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable ([String: Any]) async throws -> String

    /// Dynamic typed argument container matching the Foundation Models argument contract.
    public struct Arguments: Codable, Sendable {
        public var parameters: [String: String]

        public init(parameters: [String: String] = [:]) {
            self.parameters = parameters
        }

        public init(dictionary: [String: Any]) {
            var map: [String: String] = [:]
            for (key, value) in dictionary {
                map[key] = String(describing: value)
            }
            self.parameters = map
        }

        public func asDictionary() -> [String: Any] {
            var dict: [String: Any] = [:]
            for (k, v) in parameters {
                dict[k] = v
            }
            return dict
        }

        public subscript(key: String) -> String? {
            parameters[key]
        }
    }

    public init(
        descriptor: MCPToolDescriptor,
        executeHandler: @escaping @Sendable ([String: Any]) async throws -> String
    ) {
        self.name = descriptor.name
        self.description = descriptor.description ?? ""
        self.descriptor = descriptor
        self.executeHandler = executeHandler
    }

    public init(
        descriptor: MCPToolDescriptor,
        executeHandler: @escaping @Sendable (Arguments) async throws -> String
    ) {
        self.name = descriptor.name
        self.description = descriptor.description ?? ""
        self.descriptor = descriptor
        self.executeHandler = { dict in
            try await executeHandler(Arguments(dictionary: dict))
        }
    }

    public func call(arguments: [String: Any]) async throws -> String {
        try await executeHandler(arguments)
    }

    public func call(arguments: Arguments) async throws -> String {
        try await executeHandler(arguments.asDictionary())
    }
}
#endif

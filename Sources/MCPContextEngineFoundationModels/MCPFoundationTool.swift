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

/// Type-preserving dynamic argument value representation for tool arguments.
/// Prevents lossy String coercion by faithfully decoding and encoding Int, Double,
/// Bool, String, nested Arrays, and nested Objects.
public enum DynamicArgumentValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([DynamicArgumentValue])
    case object([String: DynamicArgumentValue])
    case null

    public var rawValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { $0.rawValue }
        case .object(let o): return o.mapValues { $0.rawValue }
        case .null: return NSNull()
        }
    }

    public init(anyValue: Any) {
        switch anyValue {
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .int(i)
        case let d as Double: self = .double(d)
        case let f as Float: self = .double(Double(f))
        case let a as [Any]: self = .array(a.map { DynamicArgumentValue(anyValue: $0) })
        case let d as [String: Any]: self = .object(d.mapValues { DynamicArgumentValue(anyValue: $0) })
        default: self = .string(String(describing: anyValue))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        if let a = try? container.decode([DynamicArgumentValue].self) {
            self = .array(a)
            return
        }
        if let o = try? container.decode([String: DynamicArgumentValue].self) {
            self = .object(o)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported dynamic argument value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        case .null: try container.encodeNil()
        }
    }
}

/// Shared dynamic typed argument container matching the Foundation Models argument contract.
/// Faithfully preserves primitive types (Int, Double, Bool, Array, Object) across model calls.
public struct AppleMCPToolArguments: Codable, Sendable {
    public var parameters: [String: DynamicArgumentValue]

    public init(parameters: [String: DynamicArgumentValue] = [:]) {
        self.parameters = parameters
    }

    public init(parameters: [String: String]) {
        self.parameters = parameters.mapValues { .string($0) }
    }

    public init(dictionary: [String: Any]) {
        var map: [String: DynamicArgumentValue] = [:]
        for (key, value) in dictionary {
            map[key] = DynamicArgumentValue(anyValue: value)
        }
        self.parameters = map
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for (k, v) in parameters {
            dict[k] = v.rawValue
        }
        return dict
    }

    public subscript(key: String) -> Any? {
        parameters[key]?.rawValue
    }

    public func string(for key: String) -> String? {
        if case .string(let s) = parameters[key] { return s }
        return nil
    }

    public func int(for key: String) -> Int? {
        if case .int(let i) = parameters[key] { return i }
        if case .double(let d) = parameters[key] { return Int(d) }
        if case .string(let s) = parameters[key] { return Int(s) }
        return nil
    }

    public func double(for key: String) -> Double? {
        if case .double(let d) = parameters[key] { return d }
        if case .int(let i) = parameters[key] { return Double(i) }
        if case .string(let s) = parameters[key] { return Double(s) }
        return nil
    }

    public func bool(for key: String) -> Bool? {
        if case .bool(let b) = parameters[key] { return b }
        if case .string(let s) = parameters[key] {
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
        }
        return nil
    }

    public func array(for key: String) -> [Any]? {
        if case .array(let arr) = parameters[key] {
            return arr.map { $0.rawValue }
        }
        return nil
    }

    public func object(for key: String) -> [String: Any]? {
        if case .object(let obj) = parameters[key] {
            return obj.mapValues { $0.rawValue }
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        struct DynamicCodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
        }

        if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            if keyedContainer.allKeys.count == 1,
               let firstKey = keyedContainer.allKeys.first,
               firstKey.stringValue == "parameters",
               let nested = try? keyedContainer.decode([String: DynamicArgumentValue].self, forKey: firstKey) {
                self.parameters = nested
                return
            }
            var map: [String: DynamicArgumentValue] = [:]
            for key in keyedContainer.allKeys {
                if let val = try? keyedContainer.decode(DynamicArgumentValue.self, forKey: key) {
                    map[key.stringValue] = val
                }
            }
            self.parameters = map
            return
        }

        let container = try decoder.singleValueContainer()
        self.parameters = try container.decode([String: DynamicArgumentValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(parameters)
    }
}

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
    public typealias Arguments = AppleMCPToolArguments

    public let name: String
    public let description: String
    public let descriptor: MCPToolDescriptor
    public let executeHandler: @Sendable (Arguments) async throws -> String

    @available(macOS 15.0, iOS 18.0, *)
    public var parameters: GenerationSchema {
        descriptor.asGenerationSchema()
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
    /// Maps integer to Int, number to Double, boolean to Bool, strings with enum constraints,
    /// arrays, and object descriptions accurately.
    public func asDynamicGenerationSchema() -> DynamicGenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        for (propName, propSchema) in inputSchema.properties {
            let schemaType: DynamicGenerationSchema
            switch propSchema.type.lowercased() {
            case "number":
                schemaType = DynamicGenerationSchema(type: Double.self)
            case "integer", "int":
                schemaType = DynamicGenerationSchema(type: Int.self)
            case "boolean", "bool":
                schemaType = DynamicGenerationSchema(type: Bool.self)
            case "array":
                schemaType = DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self))
            case "object":
                schemaType = DynamicGenerationSchema(name: propName, properties: [])
            default:
                if let allowed = propSchema.enum, !allowed.isEmpty {
                    schemaType = DynamicGenerationSchema(name: propName, anyOf: allowed)
                } else {
                    schemaType = DynamicGenerationSchema(type: String.self)
                }
            }

            if let desc = propSchema.description, !desc.isEmpty {
                properties.append(DynamicGenerationSchema.Property(name: propName, description: desc, schema: schemaType))
            } else {
                properties.append(DynamicGenerationSchema.Property(name: propName, schema: schemaType))
            }
        }
        return DynamicGenerationSchema(
            name: "\(name)_Parameters",
            description: description,
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
    public typealias Arguments = AppleMCPToolArguments

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

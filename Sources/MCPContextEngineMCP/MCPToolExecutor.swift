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
            guard let descriptor = await registry.tool(byId: identifier) else {
                throw MCPClientError.toolNotFound("Tool metadata not found for ID '\(identifier)'.")
            }
            guard let client = await registry.client(forToolId: identifier) else {
                throw MCPClientError.toolNotFound("No registered server provides tool with ID '\(identifier)'.")
            }
            try validateArguments(arguments, against: descriptor.inputSchema)
            return try await client.callTool(name: descriptor.name, arguments: arguments)
        }

        // 2. Resolve by bare name
        let descriptor = try await registry.uniqueTool(named: identifier)
        guard let client = await registry.client(forToolId: descriptor.id) else {
            throw MCPClientError.toolNotFound("No registered server provides tool '\(identifier)'.")
        }
        try validateArguments(arguments, against: descriptor.inputSchema)
        return try await client.callTool(name: descriptor.name, arguments: arguments)
    }

    /// Validates invocation arguments against the tool's defined input schema.
    private func validateArguments(_ arguments: [String: Any], against schema: ToolInputSchema) throws {
        // 1. Validate required fields
        for req in schema.required {
            if arguments[req] == nil {
                throw ArgumentValidationError.missingRequired(req)
            }
        }

        // 2. Validate known property types and enum constraints
        for (key, val) in arguments {
            guard let prop = schema.properties[key] else {
                continue
            }

            switch prop.type.lowercased() {
            case "string":
                guard let strVal = val as? String else {
                    throw ArgumentValidationError.invalidType(name: key, expected: "string")
                }
                if let allowedEnums = prop.enum, !allowedEnums.isEmpty {
                    if !allowedEnums.contains(strVal) {
                        throw ArgumentValidationError.invalidEnum(name: key, value: strVal)
                    }
                }
            case "integer", "int":
                guard val is Int else {
                    throw ArgumentValidationError.invalidType(name: key, expected: "integer")
                }
            case "number", "double", "float":
                guard val is Double || val is Int || val is Float else {
                    throw ArgumentValidationError.invalidType(name: key, expected: "number")
                }
            case "boolean", "bool":
                guard val is Bool else {
                    throw ArgumentValidationError.invalidType(name: key, expected: "boolean")
                }
            case "array":
                guard val is [Any] else {
                    throw ArgumentValidationError.invalidType(name: key, expected: "array")
                }
            case "object":
                guard val is [String: Any] else {
                    throw ArgumentValidationError.invalidType(name: key, expected: "object")
                }
            default:
                break
            }
        }
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

/// Errors raised during tool argument validation against the tool's schema descriptor.
public enum ArgumentValidationError: Error, LocalizedError {
    /// A required argument field is missing from the invocation parameters.
    case missingRequired(String)

    /// An argument has an incompatible runtime type.
    case invalidType(name: String, expected: String)

    /// A string argument does not match any of the permitted enum values.
    case invalidEnum(name: String, value: String)

    /// An unknown argument was provided.
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case .missingRequired(let name):
            return "Missing required argument: '\(name)'."
        case .invalidType(let name, let expected):
            return "Invalid type for argument '\(name)'; expected \(expected)."
        case .invalidEnum(let name, let value):
            return "Invalid value '\(value)' for argument '\(name)'; does not match allowed enum choices."
        case .unknownArgument(let name):
            return "Unknown argument '\(name)' provided."
        }
    }
}

/// Errors occurring during tool identity resolution or authorization enforcement.
public enum ExecutionSecurityError: Error, LocalizedError {
    case unauthorizedTool(String)
    case ambiguousTool(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorizedTool(let msg), .ambiguousTool(let msg):
            return msg
        }
    }
}

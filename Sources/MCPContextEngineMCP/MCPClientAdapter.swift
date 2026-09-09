import Foundation
import MCPContextEngineCore

#if canImport(MCP)
import MCP
#if canImport(System)
import System
#else
import SystemPackage
#endif
#endif

/// Protocol defining interactions with an MCP server (tool discovery and execution).
public protocol MCPClientProtocol: Sendable {
    var serverId: String { get }
    func connect() async throws
    func listTools() async throws -> [MCPToolDescriptor]
    func callTool(name: String, arguments: [String: Any]) async throws -> String
}

/// Simulated in-memory MCP client for deterministic testing, benchmarks, and offline operation.
public final class MockMCPClient: MCPClientProtocol, @unchecked Sendable {
    public let serverId: String
    private var registeredTools: [MCPToolDescriptor]
    private var toolHandlers: [String: @Sendable ([String: Any]) async throws -> String]

    public init(
        serverId: String,
        tools: [MCPToolDescriptor] = [],
        handlers: [String: @Sendable ([String: Any]) async throws -> String] = [:]
    ) {
        self.serverId = serverId
        self.registeredTools = tools
        self.toolHandlers = handlers
    }

    public func connect() async throws {}

    public func listTools() async throws -> [MCPToolDescriptor] {
        return registeredTools
    }

    public func addTool(_ tool: MCPToolDescriptor, handler: (@Sendable ([String: Any]) async throws -> String)? = nil) {
        registeredTools.append(tool)
        if let handler = handler {
            toolHandlers[tool.name] = handler
        }
    }

    public func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let handler = toolHandlers[name] else {
            return "{\"status\": \"success\", \"tool\": \"\(name)\", \"result\": \"mock_executed\"}"
        }
        return try await handler(arguments)
    }
}

#if canImport(MCP)
/// Production MCP client adapter bridging to the official Model Context Protocol Swift SDK (`MCP.Client`).
public final class StdioMCPClientAdapter: MCPClientProtocol, @unchecked Sendable {
    public let serverId: String
    public let command: String
    public let arguments: [String]
    public let environment: [String: String]

    private var client: MCP.Client?
    private var process: Process?
    private var isConnected = false

    public init(
        serverId: String,
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        self.serverId = serverId
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    public func connect() async throws {
        guard !isConnected else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = arguments
        if !environment.isEmpty {
            proc.environment = environment
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe

        try proc.run()
        self.process = proc

        #if canImport(System)
        let transport = StdioTransport(
            input: System.FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor),
            output: System.FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor)
        )
        #else
        let transport = StdioTransport(
            input: FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor),
            output: FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor)
        )
        #endif
        let mcpClient = MCP.Client(name: "MCPContextEngine", version: "1.0.0")
        try await mcpClient.connect(transport: transport)

        self.client = mcpClient
        self.isConnected = true
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        guard let client = client, isConnected else {
            throw MCPClientError.notConnected
        }

        let (mcpTools, _) = try await client.listTools()
        return mcpTools.map { mcpTool in
            MCPToolDescriptor(
                name: mcpTool.name,
                description: mcpTool.description,
                inputSchema: parseSchema(mcpTool.inputSchema),
                serverId: self.serverId,
                tags: [self.serverId]
            )
        }
    }

    /// Converts MCP SDK JSON schema value into the engine's lightweight ToolInputSchema.
    private func parseSchema(_ schemaValue: Value?) -> ToolInputSchema {
        guard case .object(let obj) = schemaValue else {
            return .empty
        }

        var properties: [String: ToolInputSchema.PropertyDescriptor] = [:]
        var required: [String] = []

        if case .object(let props) = obj["properties"] {
            for (propName, propValue) in props {
                guard case .object(let propObj) = propValue else { continue }
                let type: String
                if case .string(let t) = propObj["type"] { type = t } else { type = "string" }
                let description: String?
                if case .string(let d) = propObj["description"] { description = d } else { description = nil }
                properties[propName] = ToolInputSchema.PropertyDescriptor(type: type, description: description)
            }
        }

        if case .array(let req) = obj["required"] {
            required = req.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }

        return ToolInputSchema(type: "object", properties: properties, required: required)
    }

    public func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let client = client, isConnected else {
            throw MCPClientError.notConnected
        }

        let mcpArgs = convertToMCPValues(arguments)
        let (content, _) = try await client.callTool(name: name, arguments: mcpArgs)

        return content.compactMap { contentItem in
            if case .text(let text, _, _) = contentItem {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private func convertToMCPValues(_ dict: [String: Any]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, val) in dict {
            result[key] = convertToMCPValue(val)
        }
        return result
    }

    private func convertToMCPValue(_ val: Any) -> Value {
        if let str = val as? String { return .string(str) }
        if let int = val as? Int { return .int(int) }
        if let dbl = val as? Double { return .double(dbl) }
        if let bool = val as? Bool { return .bool(bool) }
        if let dict = val as? [String: Any] { return .object(convertToMCPValues(dict)) }
        if let arr = val as? [Any] { return .array(arr.map { convertToMCPValue($0) }) }
        return .null
    }

    deinit {
        if let process = process, process.isRunning {
            process.terminate()
        }
    }
}
#endif

public enum MCPClientError: Error, LocalizedError {
    case notConnected
    case executionFailed(String)
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP Client is not connected to server."
        case .executionFailed(let reason):
            return "MCP tool execution failed: \(reason)"
        case .toolNotFound(let name):
            return "MCP tool not found: \(name)"
        }
    }
}

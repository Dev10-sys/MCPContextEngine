import Foundation
import MCPContextEngineCore

/// Centralized thread-safe registry that discovers, catalogs, and indexes tools across
/// multiple heterogeneous MCP servers (e.g. GitHub, Filesystem, Everything, Slack).
public actor MCPToolRegistry {
    private var clients: [String: MCPClientProtocol] = [:]
    private var registeredTools: [String: MCPToolDescriptor] = [:]
    private var serverToolIndex: [String: Set<String>] = [:]

    public init() {}

    /// Registers an MCP server client with the registry.
    public func registerServer(_ client: MCPClientProtocol) {
        clients[client.serverId] = client
    }

    /// Connects to all registered MCP servers and discovers available tools concurrently.
    public func discoverAllTools() async throws -> [MCPToolDescriptor] {
        var allDiscovered: [MCPToolDescriptor] = []

        try await withThrowingTaskGroup(of: (String, [MCPToolDescriptor]).self) { group in
            for (serverId, client) in clients {
                group.addTask {
                    try await client.connect()
                    let tools = try await client.listTools()
                    return (serverId, tools)
                }
            }

            for try await (serverId, tools) in group {
                var toolNames: Set<String> = []
                for tool in tools {
                    registeredTools[tool.name] = tool
                    toolNames.insert(tool.name)
                    allDiscovered.append(tool)
                }
                serverToolIndex[serverId] = toolNames
            }
        }

        return allDiscovered
    }

    /// Looks up a registered tool descriptor by tool name.
    public func tool(named name: String) -> MCPToolDescriptor? {
        registeredTools[name]
    }

    /// Retrieves all currently registered tool descriptors.
    public func allTools() -> [MCPToolDescriptor] {
        Array(registeredTools.values).sorted { $0.name < $1.name }
    }

    /// Retrieves the client associated with a given tool name.
    public func client(forToolName name: String) -> MCPClientProtocol? {
        guard let tool = registeredTools[name] else { return nil }
        return clients[tool.serverId]
    }
}

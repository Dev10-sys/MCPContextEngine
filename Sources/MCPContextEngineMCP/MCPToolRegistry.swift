import Foundation
import MCPContextEngineCore

/// Centralized thread-safe registry that discovers, catalogs, and indexes tools across
/// multiple heterogeneous MCP servers (e.g. GitHub, Filesystem, Everything, Slack).
///
/// Tools are indexed by their fully-qualified identifier (`serverId:name`) to prevent
/// name collisions when multiple servers expose tools with identical names.
public actor MCPToolRegistry {
    private var clients: [String: MCPClientProtocol] = [:]

    /// Keyed by tool.id = "serverId:name" to prevent cross-server name collisions.
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
                var toolIds: Set<String> = []
                for tool in tools {
                    registeredTools[tool.id] = tool
                    toolIds.insert(tool.id)
                    allDiscovered.append(tool)
                }
                serverToolIndex[serverId] = toolIds
            }
        }

        return allDiscovered
    }

    /// Looks up a registered tool descriptor by fully-qualified ID ("serverId:name").
    public func tool(byId id: String) -> MCPToolDescriptor? {
        registeredTools[id]
    }

    /// Looks up a tool by bare name. Returns the first match if multiple servers expose
    /// a tool with the same name. Prefer `tool(byId:)` in multi-server environments.
    public func tool(named name: String) -> MCPToolDescriptor? {
        registeredTools.values.first { $0.name == name }
    }

    /// Retrieves all currently registered tool descriptors.
    public func allTools() -> [MCPToolDescriptor] {
        Array(registeredTools.values).sorted { $0.id < $1.id }
    }

    /// Returns all registered tool descriptors sharing the given bare tool name across all servers.
    public func tools(named name: String) -> [MCPToolDescriptor] {
        registeredTools.values.filter { $0.name == name }.sorted { $0.id < $1.id }
    }

    /// Checks if a bare tool name is provided by more than one registered MCP server.
    public func isAmbiguous(toolName: String) -> Bool {
        tools(named: toolName).count > 1
    }

    /// Retrieves the client associated with a given tool's fully-qualified ID.
    public func client(forToolId id: String) -> MCPClientProtocol? {
        guard let tool = registeredTools[id] else { return nil }
        return clients[tool.serverId]
    }

    /// Retrieves the client for a tool by bare name. Use `client(forToolId:)` in
    /// multi-server environments to avoid ambiguity.
    public func client(forToolName name: String) -> MCPClientProtocol? {
        guard let tool = registeredTools.values.first(where: { $0.name == name }) else { return nil }
        return clients[tool.serverId]
    }
}

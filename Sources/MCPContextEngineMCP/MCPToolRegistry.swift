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
    /// If a client with the same serverId already exists, the previous client is disconnected
    /// and any previously registered tools for that server are purged to maintain catalog consistency.
    public func registerServer(_ client: MCPClientProtocol) {
        if let previous = clients[client.serverId] {
            previous.disconnect()
        }
        if let previousToolIds = serverToolIndex[client.serverId] {
            for toolId in previousToolIds {
                registeredTools.removeValue(forKey: toolId)
            }
            serverToolIndex.removeValue(forKey: client.serverId)
        }
        clients[client.serverId] = client
    }

    /// Unregisters an MCP server, disconnects its client, and removes all tools registered under its namespace.
    public func unregisterServer(serverId: String) {
        if let client = clients[serverId] {
            client.disconnect()
        }
        if let previousToolIds = serverToolIndex[serverId] {
            for toolId in previousToolIds {
                registeredTools.removeValue(forKey: toolId)
            }
            serverToolIndex.removeValue(forKey: serverId)
        }
        clients.removeValue(forKey: serverId)
    }

    /// Convenience alias for registering an MCP server client.
    public func register(client: MCPClientProtocol) {
        registerServer(client)
    }

    /// Connects to all registered MCP servers and discovers available tools concurrently.
    /// Cleans up any tools that disappeared from servers since the previous discovery.
    /// Returns discovered tools in deterministic sorted order (`tool.id`).
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
                let previousToolIds = serverToolIndex[serverId] ?? []
                var newToolIds: Set<String> = []

                for tool in tools {
                    registeredTools[tool.id] = tool
                    newToolIds.insert(tool.id)
                    allDiscovered.append(tool)
                }

                // Clean up stale tools that disappeared from this server on rediscovery
                let staleToolIds = previousToolIds.subtracting(newToolIds)
                for staleId in staleToolIds {
                    registeredTools.removeValue(forKey: staleId)
                }

                serverToolIndex[serverId] = newToolIds
            }
        }

        return allDiscovered.sorted { $0.id < $1.id }
    }

    /// Discovers tools for a specific registered server, cleaning up any disappeared tools.
    public func discoverTools(forServer serverId: String) async throws -> [MCPToolDescriptor] {
        guard let client = clients[serverId] else { return [] }
        try await client.connect()
        let tools = try await client.listTools()

        let previousToolIds = serverToolIndex[serverId] ?? []
        var newToolIds: Set<String> = []
        for tool in tools {
            registeredTools[tool.id] = tool
            newToolIds.insert(tool.id)
        }
        let staleToolIds = previousToolIds.subtracting(newToolIds)
        for staleId in staleToolIds {
            registeredTools.removeValue(forKey: staleId)
        }
        serverToolIndex[serverId] = newToolIds
        return tools.sorted { $0.id < $1.id }
    }

    /// Looks up a registered tool descriptor by fully-qualified ID ("serverId:name").
    public func tool(byId id: String) -> MCPToolDescriptor? {
        registeredTools[id]
    }

    /// Looks up a registered tool descriptor by bare name when uniquely defined.
    /// If multiple servers expose a tool with the same name, returns nil to prevent ambiguity footguns.
    /// Use `uniqueTool(named:)` to throw a descriptive error, or `tools(named:)` to inspect all matches.
    public func tool(named name: String) -> MCPToolDescriptor? {
        let matches = tools(named: name)
        guard matches.count == 1 else { return nil }
        return matches.first
    }

    /// Looks up a tool by bare name, throwing an error if the name is ambiguous across servers or not found.
    public func uniqueTool(named name: String) throws -> MCPToolDescriptor {
        let matches = tools(named: name)
        if matches.isEmpty {
            throw MCPClientError.toolNotFound(name)
        }
        if matches.count > 1 {
            let candidates = matches.map(\.id).joined(separator: ", ")
            throw ExecutionSecurityError.ambiguousTool(
                "Execution of tool '\(name)' is ambiguous across multiple registered servers: \(candidates). Please specify fully-qualified identifier ('serverId:name')."
            )
        }
        return matches[0]
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

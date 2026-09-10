import XCTest
import MCPContextEngineCore
@testable import MCPContextEngineMCP

final class MCPRegistryTests: XCTestCase {
    func testMultiServerDiscovery() async throws {
        let registry = MCPToolRegistry()

        let githubTools = [
            MCPToolDescriptor(name: "github_search_issues", serverId: "github"),
            MCPToolDescriptor(name: "github_get_issue", serverId: "github")
        ]
        let everythingTools = [
            MCPToolDescriptor(name: "everything_echo", serverId: "everything"),
            MCPToolDescriptor(name: "everything_sample", serverId: "everything")
        ]

        let mockGitHub = MockMCPClient(serverId: "github", tools: githubTools)
        let mockEverything = MockMCPClient(serverId: "everything", tools: everythingTools)

        await registry.registerServer(mockGitHub)
        await registry.registerServer(mockEverything)

        let discovered = try await registry.discoverAllTools()
        XCTAssertEqual(discovered.count, 4)

        let foundGithub = await registry.tool(named: "github_search_issues")
        XCTAssertNotNil(foundGithub)
        XCTAssertEqual(foundGithub?.serverId, "github")

        let foundEcho = await registry.tool(named: "everything_echo")
        XCTAssertNotNil(foundEcho)
        XCTAssertEqual(foundEcho?.serverId, "everything")
    }

    func testStaleToolPurgedOnRediscovery() async throws {
        let registry = MCPToolRegistry()

        let initialTools = [
            MCPToolDescriptor(name: "tool_a", serverId: "srv"),
            MCPToolDescriptor(name: "tool_b", serverId: "srv"),
            MCPToolDescriptor(name: "tool_c", serverId: "srv")
        ]
        let mockClient = MockMCPClient(serverId: "srv", tools: initialTools)
        await registry.registerServer(mockClient)

        let firstDiscovery = try await registry.discoverAllTools()
        XCTAssertEqual(firstDiscovery.count, 3)
        let toolCBefore = await registry.tool(byId: "srv:tool_c")
        XCTAssertNotNil(toolCBefore)

        // Server updates exposed tools: tool_c disappeared
        let updatedTools = [
            MCPToolDescriptor(name: "tool_a", serverId: "srv"),
            MCPToolDescriptor(name: "tool_b", serverId: "srv")
        ]
        let updatedClient = MockMCPClient(serverId: "srv", tools: updatedTools)
        await registry.registerServer(updatedClient)

        let secondDiscovery = try await registry.discoverAllTools()
        XCTAssertEqual(secondDiscovery.count, 2)
        let toolCAfter = await registry.tool(byId: "srv:tool_c")
        XCTAssertNil(toolCAfter, "Stale tool_c should be purged on re-discovery")
        let toolA = await registry.tool(byId: "srv:tool_a")
        XCTAssertNotNil(toolA)
        let toolB = await registry.tool(byId: "srv:tool_b")
        XCTAssertNotNil(toolB)
    }

    func testStaleToolsPurgedOnServerUnregister() async throws {
        let registry = MCPToolRegistry()
        let tools = [MCPToolDescriptor(name: "temp_tool", serverId: "temp")]
        let client = MockMCPClient(serverId: "temp", tools: tools)
        await registry.registerServer(client)
        _ = try await registry.discoverAllTools()
        let tempToolBefore = await registry.tool(byId: "temp:temp_tool")
        XCTAssertNotNil(tempToolBefore)

        await registry.unregisterServer(serverId: "temp")
        let tempToolAfter = await registry.tool(byId: "temp:temp_tool")
        XCTAssertNil(tempToolAfter)
    }

    func testReplacingServerDisconnectsPreviousClient() async throws {
        let registry = MCPToolRegistry()
        let clientV1 = MockMCPClient(serverId: "srv", tools: [MCPToolDescriptor(name: "tool_v1", serverId: "srv")])
        try await clientV1.connect()
        XCTAssertTrue(clientV1.isCurrentlyConnected)

        await registry.registerServer(clientV1)
        XCTAssertEqual(clientV1.disconnectCallCount, 0)

        // Register new client with same serverId
        let clientV2 = MockMCPClient(serverId: "srv", tools: [MCPToolDescriptor(name: "tool_v2", serverId: "srv")])
        await registry.registerServer(clientV2)

        XCTAssertFalse(clientV1.isCurrentlyConnected, "Previous client must be disconnected on replacement")
        XCTAssertEqual(clientV1.disconnectCallCount, 1)
    }

    func testUnregisteringServerDisconnectsClient() async throws {
        let registry = MCPToolRegistry()
        let client = MockMCPClient(serverId: "srv", tools: [MCPToolDescriptor(name: "tool_1", serverId: "srv")])
        try await client.connect()
        XCTAssertTrue(client.isCurrentlyConnected)

        await registry.registerServer(client)
        await registry.unregisterServer(serverId: "srv")

        XCTAssertFalse(client.isCurrentlyConnected, "Client must be disconnected when server is unregistered")
        XCTAssertEqual(client.disconnectCallCount, 1)
    }

    func testDeterministicDiscoveryOrdering() async throws {
        let registry = MCPToolRegistry()
        let clientA = MockMCPClient(serverId: "z_srv", tools: [MCPToolDescriptor(name: "tool_z", serverId: "z_srv")])
        let clientB = MockMCPClient(serverId: "a_srv", tools: [MCPToolDescriptor(name: "tool_a", serverId: "a_srv")])
        let clientC = MockMCPClient(serverId: "m_srv", tools: [MCPToolDescriptor(name: "tool_m", serverId: "m_srv")])

        await registry.registerServer(clientA)
        await registry.registerServer(clientB)
        await registry.registerServer(clientC)

        let discovered = try await registry.discoverAllTools()
        let discoveredIds = discovered.map(\.id)
        let sortedIds = discoveredIds.sorted()
        XCTAssertEqual(discoveredIds, sortedIds, "discoverAllTools must return descriptors in deterministic sorted order")
    }

    func testUniqueToolNamedThrowsOnAmbiguity() async throws {
        let registry = MCPToolRegistry()
        let client1 = MockMCPClient(serverId: "srv1", tools: [MCPToolDescriptor(name: "shared_tool", serverId: "srv1")])
        let client2 = MockMCPClient(serverId: "srv2", tools: [MCPToolDescriptor(name: "shared_tool", serverId: "srv2")])

        await registry.registerServer(client1)
        await registry.registerServer(client2)
        _ = try await registry.discoverAllTools()

        // tool(named:) returns nil on ambiguity
        let ambiguousTool = await registry.tool(named: "shared_tool")
        XCTAssertNil(ambiguousTool, "tool(named:) should return nil when multiple servers provide the same tool name")

        // uniqueTool(named:) throws
        do {
            _ = try await registry.uniqueTool(named: "shared_tool")
            XCTFail("uniqueTool(named:) must throw when multiple servers expose the same tool name")
        } catch {
            // Expected
        }
    }
}

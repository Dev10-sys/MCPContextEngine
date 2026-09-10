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
}

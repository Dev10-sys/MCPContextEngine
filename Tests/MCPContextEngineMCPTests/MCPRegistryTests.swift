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
}

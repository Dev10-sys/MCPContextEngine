import XCTest
import MCPContextEngineCore
@testable import MCPContextEngineMCP

final class MCPExecutionTests: XCTestCase {
    func testApprovedToolExecutionSucceeds() async throws {
        let registry = MCPToolRegistry()
        let tool = MCPToolDescriptor(name: "github_search_issues", serverId: "github")
        let client = MockMCPClient(
            serverId: "github",
            tools: [tool],
            handlers: [
                "github_search_issues": { args in
                    return "{\"issues\": [{\"id\": 92004, \"title\": \"Swift concurrency issue\"}]}"
                }
            ]
        )
        await registry.registerServer(client)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)
        let approved: Set<String> = ["github_search_issues"]

        let result = try await executor.execute(
            name: "github_search_issues",
            arguments: ["query": "concurrency"],
            approvedToolNames: approved
        )

        XCTAssertTrue(result.contains("92004"))
    }

    func testUnapprovedToolExecutionBlockedBySecurityPolicy() async throws {
        let registry = MCPToolRegistry()
        let tool = MCPToolDescriptor(name: "danger_tool", serverId: "test")
        let client = MockMCPClient(serverId: "test", tools: [tool])
        await registry.registerServer(client)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)
        let approved: Set<String> = ["safe_tool"]

        do {
            _ = try await executor.execute(
                name: "danger_tool",
                arguments: [:],
                approvedToolNames: approved
            )
            XCTFail("Executing unapproved tool should throw an ExecutionSecurityError")
        } catch let error as ExecutionSecurityError {
            XCTAssertTrue(error.localizedDescription.contains("blocked by MCPContextEngine security policy"))
        }
    }
}

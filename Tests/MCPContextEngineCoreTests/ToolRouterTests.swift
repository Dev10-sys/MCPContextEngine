import XCTest
@testable import MCPContextEngineCore

final class ToolRouterTests: XCTestCase {
    var router: ToolRouter!
    var tools: [MCPToolDescriptor]!

    override func setUp() {
        super.setUp()
        router = ToolRouter()

        tools = [
            MCPToolDescriptor(name: "github_search_issues", description: "Search GitHub issues by query.", serverId: "github"),
            MCPToolDescriptor(name: "github_get_issue", description: "Retrieve issue details by number.", serverId: "github"),
            MCPToolDescriptor(name: "github_create_pull_request", description: "Create a PR in a repo.", serverId: "github"),
            MCPToolDescriptor(name: "fs_read_file", description: "Read file contents from disk.", serverId: "filesystem"),
            MCPToolDescriptor(name: "fs_list_directory", description: "List files in directory.", serverId: "filesystem"),
            MCPToolDescriptor(name: "calendar_create_event", description: "Create calendar event.", serverId: "calendar"),
            MCPToolDescriptor(name: "calendar_list_events", description: "List upcoming calendar events.", serverId: "calendar"),
            MCPToolDescriptor(name: "slack_send_message", description: "Post message to Slack.", serverId: "slack"),
            MCPToolDescriptor(name: "db_execute_query", description: "Run SQL statement.", serverId: "database"),
            MCPToolDescriptor(name: "everything_echo", description: "Echo testing payload.", serverId: "everything")
        ]
    }

    func testToolSelectionRanksIssueToolsTop() {
        let task = "Find open Swift concurrency issues related to our project"
        let result = router.route(tools: tools, forTask: task, topK: 3)

        XCTAssertEqual(result.selectedTools.count, 2, "Only relevant tools matching the task should be selected")
        XCTAssertEqual(result.selectedTools.first?.name, "github_search_issues")
        XCTAssertEqual(result.selectedTools[1].name, "github_get_issue")
    }

    func testTopKLimitRespected() {
        let task = "issues"
        let result = router.route(tools: tools, forTask: task, topK: 1)

        XCTAssertEqual(result.selectedTools.count, 1)
    }

    func testThresholdFiltersNoise() {
        let task = "find open swift concurrency issues"
        let result = router.route(tools: tools, forTask: task, topK: 10, minScoreThreshold: 0.20)

        for scored in result.selectedScores {
            XCTAssertGreaterThanOrEqual(scored.score, 0.20)
        }
        let unselectedNames = Set(result.unselectedTools.map(\.name))
        XCTAssertTrue(unselectedNames.contains("calendar_create_event"))
        XCTAssertTrue(unselectedNames.contains("calendar_list_events"))
        XCTAssertTrue(unselectedNames.contains("slack_send_message"))
    }

    func testMaxSchemaTokensRejectsOversizedFirstTool() {
        let tool = MCPToolDescriptor(
            name: "very_large_tool",
            description: String(repeating: "Extremely long tool description consuming dozens of tokens. ", count: 20),
            serverId: "server"
        )
        let result = router.route(
            tools: [tool],
            forTask: "large tool",
            topK: 4,
            maxSchemaTokens: 10
        )
        XCTAssertTrue(result.selectedTools.isEmpty, "Tool exceeding maxSchemaTokens must not be selected even if it is the first candidate")
    }

    func testMaxSchemaTokensSelectsFittingToolsOnly() {
        let smallTool = MCPToolDescriptor(name: "small_tool", description: "Small.", serverId: "srv")
        let giantTool = MCPToolDescriptor(
            name: "giant_tool",
            description: String(repeating: "Huge description ", count: 50),
            serverId: "srv"
        )
        let result = router.route(
            tools: [giantTool, smallTool],
            forTask: "tool",
            topK: 4,
            maxSchemaTokens: 25
        )
        XCTAssertTrue(result.selectedTools.contains { $0.name == "small_tool" })
        XCTAssertFalse(result.selectedTools.contains { $0.name == "giant_tool" })
    }
}

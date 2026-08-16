import XCTest
@testable import MCPContextEngineCore

final class ToolScorerTests: XCTestCase {
    var scorer: ToolScorer!

    override func setUp() {
        super.setUp()
        scorer = ToolScorer()
    }

    func testExactNameAndConceptMatchScoresHigh() {
        let tool = MCPToolDescriptor(
            name: "github_search_issues",
            description: "Search issues across GitHub repositories matching query, labels, and state.",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: ["query": .init(type: "string", description: "Search query")]
            ),
            serverId: "github"
        )

        let task = "Find open Swift concurrency issues"
        let score = scorer.score(tool: tool, forTask: task)

        XCTAssertGreaterThan(score.score, 0.30, "Relevant GitHub issues tool should have a strong score")
        XCTAssertGreaterThan(score.breakdown.nameMatchScore, 0.0, "Name should match 'issues'")
        XCTAssertGreaterThan(score.breakdown.descriptionMatchScore, 0.0, "Description should match query keywords")
    }

    func testUnrelatedToolScoresLowOrZero() {
        let tool = MCPToolDescriptor(
            name: "calendar_create_event",
            description: "Schedule a calendar event with attendee invites and location.",
            inputSchema: ToolInputSchema(type: "object", properties: [:]),
            serverId: "calendar"
        )

        let task = "Find open Swift concurrency issues"
        let score = scorer.score(tool: tool, forTask: task)

        XCTAssertLessThan(score.score, 0.15, "Completely unrelated calendar tool must receive a negligible score")
    }

    func testTokenizeStripsPunctuationAndStopwords() {
        let text = "Please, find all of the relevant Swift concurrency issues for our team!"
        let tokens = ToolScorer.tokenize(text)

        XCTAssertTrue(tokens.contains("swift"))
        XCTAssertTrue(tokens.contains("concurrency"))
        XCTAssertTrue(tokens.contains("issues"))
        XCTAssertFalse(tokens.contains("the"))
        XCTAssertFalse(tokens.contains("of"))
        XCTAssertFalse(tokens.contains("for"))
        XCTAssertFalse(tokens.contains("our"))
    }
}

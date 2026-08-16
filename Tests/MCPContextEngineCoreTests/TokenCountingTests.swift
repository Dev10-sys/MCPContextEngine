import XCTest
@testable import MCPContextEngineCore

final class TokenCountingTests: XCTestCase {
    func testMockTokenProviderCalculation() {
        let provider = MockTokenProvider(averageCharsPerToken: 4.0)

        XCTAssertEqual(provider.countTokens(text: ""), 0)
        XCTAssertEqual(provider.countTokens(text: "1234"), 1)
        XCTAssertEqual(provider.countTokens(text: "12345678"), 2)
        XCTAssertEqual(provider.countTokens(text: "123456789"), 3)
    }

    func testEstimatedSchemaTokens() {
        let tool = MCPToolDescriptor(
            name: "github_search_issues",
            description: "Search issues on GitHub.",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: ["query": .init(type: "string", description: "Search query string")]
            ),
            serverId: "github"
        )

        let tokens = tool.estimatedSchemaTokens()
        XCTAssertGreaterThan(tokens, 0)
        XCTAssertLessThan(tokens, 100)
    }
}

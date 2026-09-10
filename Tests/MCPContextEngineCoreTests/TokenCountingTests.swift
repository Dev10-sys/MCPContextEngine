import XCTest
@testable import MCPContextEngineCore

final class TokenCountingTests: XCTestCase {
    func testMockTokenProviderCalculation() {
        let provider = CalibratedTokenProvider(averageCharsPerToken: 4.0)

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

    func testEstimatedSchemaTokensReflectsInputSchemaChanges() {
        let provider = CalibratedTokenProvider(averageCharsPerToken: 4.0)
        let baseTool = MCPToolDescriptor(
            name: "tool",
            description: "A tool.",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: ["param": .init(type: "string")]
            ),
            serverId: "srv"
        )
        let baseTokens = baseTool.estimatedSchemaTokens(using: provider)

        let toolWithRequired = MCPToolDescriptor(
            name: "tool",
            description: "A tool.",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: ["param": .init(type: "string")],
                required: ["param"]
            ),
            serverId: "srv"
        )
        let requiredTokens = toolWithRequired.estimatedSchemaTokens(using: provider)
        XCTAssertGreaterThan(requiredTokens, baseTokens, "Adding required fields must increase estimated tokens")

        let toolWithEnum = MCPToolDescriptor(
            name: "tool",
            description: "A tool.",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: ["param": .init(type: "string", enum: ["option_a", "option_b", "option_c"])],
                required: ["param"]
            ),
            serverId: "srv"
        )
        let enumTokens = toolWithEnum.estimatedSchemaTokens(using: provider)
        XCTAssertGreaterThan(enumTokens, requiredTokens, "Adding enum definitions must increase estimated tokens")
    }
}

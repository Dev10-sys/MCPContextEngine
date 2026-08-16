import XCTest
import MCPContextEngineCore
@testable import MCPContextEngineFoundationModels

final class FoundationModelsAdapterTests: XCTestCase {
    func testAdapterGeneratesFoundationToolDefinition() {
        let descriptor = MCPToolDescriptor(
            name: "github_search_issues",
            description: "Search issues on GitHub repository.",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: ["query": .init(type: "string", description: "Search query string")],
                required: ["query"]
            ),
            serverId: "github"
        )

        let adapter = FoundationModelsAdapter()
        let foundationDef = adapter.convertToToolDefinition(descriptor: descriptor)

        XCTAssertEqual(foundationDef.name, "github_search_issues")
        XCTAssertEqual(foundationDef.description, "Search issues on GitHub repository.")
        XCTAssertEqual(foundationDef.parametersSchema.required, ["query"])
    }

    func testRuntimeContextCapacityFallback() {
        let capacity = FoundationModelsTokenProvider.runtimeContextCapacity()
        XCTAssertGreaterThanOrEqual(capacity, 4096)
    }
}

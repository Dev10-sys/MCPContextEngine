import XCTest
import MCPContextEngineCore
import MCPContextEngineMCP
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

    func testRuntimeContextCapacityIntrospection() {
        let capacity = FoundationModelsTokenProvider.runtimeContextCapacity()
        XCTAssertGreaterThanOrEqual(capacity, 4096)

        let provider = FoundationModelsTokenProvider()
        XCTAssertEqual(provider.capacity(for: "on-device-apple-silicon"), 4096)
        XCTAssertEqual(provider.capacity(for: "apple-intelligence-pcc-cloud"), 32768)
    }

    func testFoundationModelToolExecutionAndReduction() async throws {
        let descriptor = MCPToolDescriptor(
            name: "mock_data_fetch",
            description: "Fetches diagnostic data",
            inputSchema: .empty,
            serverId: "mock_server"
        )

        let registry = MCPToolRegistry()
        let mockClient = MockMCPClient(
            serverId: "mock_server",
            tools: [descriptor],
            handlers: [
                "mock_data_fetch": { _ in
                    String(repeating: "Large diagnostic trace chunk. ", count: 50)
                }
            ]
        )
        await registry.registerServer(mockClient)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)
        let adapter = FoundationModelsAdapter()
        let bridgedTool = adapter.bridge(descriptor: descriptor, executor: executor)

        XCTAssertEqual(bridgedTool.name, "mock_data_fetch")
        XCTAssertEqual(bridgedTool.functionCallingDeclaration["name"] as? String, "mock_data_fetch")

        // Direct execution
        let raw = try await bridgedTool.execute(arguments: [:])
        XCTAssertTrue(raw.contains("Large diagnostic trace chunk"))

        // Execution with automatic budget reduction
        let reducer = ResultReducer(tokenProvider: MockTokenProvider())
        let reductionResult = try await bridgedTool.executeAndReduce(
            arguments: [:],
            availableBudgetTokens: 100,
            reducer: reducer
        )
        XCTAssertLessThanOrEqual(reductionResult.reducedTokens, 100)
    }
}

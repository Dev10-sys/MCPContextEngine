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

    func testAppleMCPToolDynamicArgumentsAndExecution() async throws {
        let descriptor = MCPToolDescriptor(
            name: "test_dynamic_tool",
            description: "Test dynamic tool execution",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: [
                    "action": .init(type: "string", description: "Action to take"),
                    "count": .init(type: "number", description: "Count parameter")
                ],
                required: ["action"]
            ),
            serverId: "test_server"
        )

        let appleTool = AppleMCPTool(descriptor: descriptor) { (args: [String: Any]) in
            let action = args["action"] as? String ?? "unknown"
            let count = args["count"] as? String ?? "0"
            return "Executed \(action) with count \(count)"
        }

        XCTAssertEqual(appleTool.name, "test_dynamic_tool")
        XCTAssertEqual(appleTool.description, "Test dynamic tool execution")

        // Test with dictionary call
        let result1 = try await appleTool.call(arguments: ["action": "analyze", "count": "42"])
        XCTAssertEqual(result1, "Executed analyze with count 42")

        // Test with typed dynamic Arguments call
        let typedArgs = AppleMCPTool.Arguments(dictionary: ["action": "compact", "count": "10"])
        XCTAssertEqual(typedArgs["action"], "compact")
        XCTAssertEqual(typedArgs["count"], "10")
        let result2 = try await appleTool.call(arguments: typedArgs)
        XCTAssertEqual(result2, "Executed compact with count 10")
    }

    func testNativeTokenCountAndContextSizeFallback() async throws {
        let provider = FoundationModelsTokenProvider()
        let sampleText = "The quick brown fox jumps over the lazy dog. Swift 6 on Apple Silicon."

        let tokenCount = try await provider.nativeTokenCount(for: sampleText)
        XCTAssertGreaterThan(tokenCount, 5)

        let contextSize = try await FoundationModelsTokenProvider.nativeContextSize()
        XCTAssertGreaterThanOrEqual(contextSize, 4096)
    }
}

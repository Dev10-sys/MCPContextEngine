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
                    "count": .init(type: "integer", description: "Count parameter"),
                    "enabled": .init(type: "boolean", description: "Enabled flag")
                ],
                required: ["action", "count"]
            ),
            serverId: "test_server"
        )

        let appleTool = AppleMCPTool(descriptor: descriptor) { (args: [String: Any]) in
            let action = args["action"] as? String ?? "unknown"
            let count = args["count"] as? Int ?? 0
            let enabled = args["enabled"] as? Bool ?? false
            return "Executed \(action) with count \(count) enabled:\(enabled)"
        }

        XCTAssertEqual(appleTool.name, "test_dynamic_tool")
        XCTAssertEqual(appleTool.description, "Test dynamic tool execution")

        // Test with dictionary call preserving true Int and Bool
        let result1 = try await appleTool.call(arguments: ["action": "analyze", "count": 42, "enabled": true])
        XCTAssertEqual(result1, "Executed analyze with count 42 enabled:true")

        // Test with typed dynamic Arguments preserving types and convenience accessors
        let typedArgs = AppleMCPTool.Arguments(dictionary: ["action": "compact", "count": 10, "enabled": false])
        XCTAssertEqual(typedArgs.string(for: "action"), "compact")
        XCTAssertEqual(typedArgs.int(for: "count"), 10)
        XCTAssertEqual(typedArgs.bool(for: "enabled"), false)
        let result2 = try await appleTool.call(arguments: typedArgs)
        XCTAssertEqual(result2, "Executed compact with count 10 enabled:false")

        // Test JSON decoding into Arguments
        let jsonString = "{\"action\": \"benchmark\", \"count\": 100, \"enabled\": true}"
        let decodedArgs = try JSONDecoder().decode(AppleMCPTool.Arguments.self, from: Data(jsonString.utf8))
        XCTAssertEqual(decodedArgs.int(for: "count"), 100)
        XCTAssertEqual(decodedArgs.bool(for: "enabled"), true)
        XCTAssertEqual(decodedArgs.string(for: "action"), "benchmark")
    }

    func testDynamicArgumentValueTypePreservation() throws {
        let original: [String: Any] = [
            "int": 42,
            "double": 3.1415,
            "bool": true,
            "string": "mcp",
            "array": ["swift", "engine"],
            "nested": ["key": 10]
        ]
        let args = AppleMCPTool.Arguments(dictionary: original)
        XCTAssertEqual(args.int(for: "int"), 42)
        XCTAssertEqual(args.double(for: "double") ?? 0.0, 3.1415, accuracy: 0.0001)
        XCTAssertEqual(args.bool(for: "bool"), true)
        XCTAssertEqual(args.string(for: "string"), "mcp")

        let recovered = args.asDictionary()
        XCTAssertEqual(recovered["int"] as? Int, 42)
        XCTAssertEqual(recovered["bool"] as? Bool, true)
        XCTAssertEqual(recovered["string"] as? String, "mcp")
        let arr = recovered["array"] as? [Any]
        XCTAssertEqual(arr?.count, 2)
        let nested = recovered["nested"] as? [String: Any]
        XCTAssertEqual(nested?["key"] as? Int, 10)
    }

    func testDynamicArgumentValidationAndErrors() throws {
        // Valid conversion
        let validDict: [String: Any] = ["count": 50, "ratio": 1.25, "active": false]
        let validated = try AppleMCPTool.Arguments(validatingDictionary: validDict)
        XCTAssertEqual(validated.int(for: "count"), 50)
        XCTAssertEqual(validated.double(for: "ratio"), 1.25)
        XCTAssertEqual(validated.bool(for: "active"), false)

        // Unsupported type throws DynamicArgumentConversionError
        struct CustomOpaqueType {}
        let invalidDict: [String: Any] = ["opaque": CustomOpaqueType()]
        XCTAssertThrowsError(try AppleMCPTool.Arguments(validatingDictionary: invalidDict)) { error in
            guard let convError = error as? DynamicArgumentConversionError else {
                XCTFail("Expected DynamicArgumentConversionError, got: \(error)")
                return
            }
            if case .unsupportedType(let desc) = convError {
                XCTAssertTrue(desc.contains("CustomOpaqueType"))
            }
        }
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

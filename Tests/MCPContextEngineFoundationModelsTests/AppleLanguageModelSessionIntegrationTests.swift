import XCTest
import MCPContextEngineCore
import MCPContextEngineMCP
@testable import MCPContextEngineFoundationModels

#if canImport(FoundationModels)
import FoundationModels

final class AppleLanguageModelSessionIntegrationTests: XCTestCase {
    func testLanguageModelSessionToolRegistrationAndExecution() async throws {
        let descriptor = MCPToolDescriptor(
            name: "calculate_sum",
            description: "Calculates the sum of two integers",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: [
                    "a": .init(type: "integer", description: "First integer operand"),
                    "b": .init(type: "integer", description: "Second integer operand")
                ],
                required: ["a", "b"]
            ),
            serverId: "math"
        )

        let appleTool = AppleMCPTool(descriptor: descriptor) { (args: AppleMCPTool.Arguments) in
            let a = args.int(for: "a") ?? 0
            let b = args.int(for: "b") ?? 0
            return "\(a + b)"
        }

        XCTAssertEqual(appleTool.name, "calculate_sum")
        XCTAssertEqual(appleTool.description, "Calculates the sum of two integers")

        // Test direct execution over typed Arguments
        let directResult = try await appleTool.call(arguments: AppleMCPTool.Arguments(dictionary: ["a": 15, "b": 27]))
        XCTAssertEqual(directResult, "42")

        // Test parameter schema generation and wiring
        if #available(macOS 15.0, iOS 18.0, *) {
            let schema = appleTool.parameters
            XCTAssertNotNil(schema, "AppleMCPTool should expose dynamic GenerationSchema parameters")
        }

        // Live LanguageModelSession test if Apple Intelligence model is available on current runner/device
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("Notice: SystemLanguageModel is not available on this host environment (Apple Intelligence not enabled/downloading). Tool conformance and parameter schema successfully verified.")
            return
        }

        let session = LanguageModelSession(tools: [appleTool])
        let response = try await session.respond(to: "Compute the sum of 15 and 27 using the calculate_sum tool.")
        XCTAssertFalse(response.content.isEmpty, "Model session should return a non-empty response")
    }
}
#else
final class AppleLanguageModelSessionIntegrationTests: XCTestCase {
    func testCrossPlatformToolBridgeAndSchema() async throws {
        let descriptor = MCPToolDescriptor(
            name: "calculate_sum",
            description: "Calculates the sum of two integers",
            inputSchema: ToolInputSchema(
                type: "object",
                properties: [
                    "a": .init(type: "integer", description: "First integer operand"),
                    "b": .init(type: "integer", description: "Second integer operand")
                ],
                required: ["a", "b"]
            ),
            serverId: "math"
        )

        let appleTool = AppleMCPTool(descriptor: descriptor) { (args: AppleMCPTool.Arguments) in
            let a = args.int(for: "a") ?? 0
            let b = args.int(for: "b") ?? 0
            return "\(a + b)"
        }

        XCTAssertEqual(appleTool.name, "calculate_sum")
        let directResult = try await appleTool.call(arguments: AppleMCPTool.Arguments(dictionary: ["a": 15, "b": 27]))
        XCTAssertEqual(directResult, "42")
    }
}
#endif

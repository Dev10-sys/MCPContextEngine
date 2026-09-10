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

    func testExecutionByFullyQualifiedIdAndDescriptor() async throws {
        let registry = MCPToolRegistry()
        let toolA = MCPToolDescriptor(name: "search", serverId: "server_a")
        let toolB = MCPToolDescriptor(name: "search", serverId: "server_b")

        let clientA = MockMCPClient(
            serverId: "server_a",
            tools: [toolA],
            handlers: ["search": { _ in "result_from_server_a" }]
        )
        let clientB = MockMCPClient(
            serverId: "server_b",
            tools: [toolB],
            handlers: ["search": { _ in "result_from_server_b" }]
        )

        await registry.registerServer(clientA)
        await registry.registerServer(clientB)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)

        // Verify ambiguity check
        let isAmbiguous = await registry.isAmbiguous(toolName: "search")
        XCTAssertTrue(isAmbiguous)

        // Execute server A explicitly by ID
        let resA = try await executor.execute(identifier: "server_a:search")
        XCTAssertEqual(resA, "result_from_server_a")

        // Execute server B explicitly by descriptor
        let resB = try await executor.execute(descriptor: toolB)
        XCTAssertEqual(resB, "result_from_server_b")
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

    func testAmbiguousBareNameExecutionThrowsError() async throws {
        let registry = MCPToolRegistry()
        let toolA = MCPToolDescriptor(name: "search", serverId: "server_a")
        let toolB = MCPToolDescriptor(name: "search", serverId: "server_b")

        let clientA = MockMCPClient(serverId: "server_a", tools: [toolA], handlers: ["search": { _ in "result_a" }])
        let clientB = MockMCPClient(serverId: "server_b", tools: [toolB], handlers: ["search": { _ in "result_b" }])

        await registry.registerServer(clientA)
        await registry.registerServer(clientB)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)

        do {
            _ = try await executor.execute(identifier: "search")
            XCTFail("Executing ambiguous bare tool name should throw ExecutionSecurityError.ambiguousTool")
        } catch let error as ExecutionSecurityError {
            if case .ambiguousTool(let msg) = error {
                XCTAssertTrue(msg.contains("ambiguous across multiple registered servers"))
            } else {
                XCTFail("Expected .ambiguousTool error, got: \(error)")
            }
        }
    }

    func testExecutorThrowsOnMissingRequiredArgument() async throws {
        let registry = MCPToolRegistry()
        let schema = ToolInputSchema(
            type: "object",
            properties: ["query": ToolInputSchema.PropertyDescriptor(type: "string")],
            required: ["query"]
        )
        let tool = MCPToolDescriptor(name: "search_tool", inputSchema: schema, serverId: "srv")
        let client = MockMCPClient(serverId: "srv", tools: [tool], handlers: ["search_tool": { _ in "ok" }])

        await registry.registerServer(client)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)
        do {
            _ = try await executor.execute(identifier: "srv:search_tool", arguments: [:])
            XCTFail("Must throw when missing required argument")
        } catch let error as ArgumentValidationError {
            if case .missingRequired(let name) = error {
                XCTAssertEqual(name, "query")
            } else {
                XCTFail("Expected .missingRequired, got \(error)")
            }
        }
    }

    func testExecutorThrowsOnInvalidType() async throws {
        let registry = MCPToolRegistry()
        let schema = ToolInputSchema(
            type: "object",
            properties: [
                "count": ToolInputSchema.PropertyDescriptor(type: "integer"),
                "tag": ToolInputSchema.PropertyDescriptor(type: "string")
            ],
            required: ["count"]
        )
        let tool = MCPToolDescriptor(name: "count_tool", inputSchema: schema, serverId: "srv")
        let client = MockMCPClient(serverId: "srv", tools: [tool], handlers: ["count_tool": { _ in "ok" }])

        await registry.registerServer(client)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)
        do {
            _ = try await executor.execute(identifier: "srv:count_tool", arguments: ["count": "not_an_int"])
            XCTFail("Must throw when argument type is invalid")
        } catch let error as ArgumentValidationError {
            if case .invalidType(let name, let expected) = error {
                XCTAssertEqual(name, "count")
                XCTAssertEqual(expected, "integer")
            } else {
                XCTFail("Expected .invalidType, got \(error)")
            }
        }
    }

    func testExecutorThrowsOnInvalidEnum() async throws {
        let registry = MCPToolRegistry()
        let schema = ToolInputSchema(
            type: "object",
            properties: [
                "format": ToolInputSchema.PropertyDescriptor(type: "string", enum: ["json", "csv", "text"])
            ],
            required: ["format"]
        )
        let tool = MCPToolDescriptor(name: "format_tool", inputSchema: schema, serverId: "srv")
        let client = MockMCPClient(serverId: "srv", tools: [tool], handlers: ["format_tool": { _ in "ok" }])

        await registry.registerServer(client)
        _ = try await registry.discoverAllTools()

        let executor = MCPToolExecutor(registry: registry)
        do {
            _ = try await executor.execute(identifier: "srv:format_tool", arguments: ["format": "xml"])
            XCTFail("Must throw when enum value is not permitted")
        } catch let error as ArgumentValidationError {
            if case .invalidEnum(let name, let val) = error {
                XCTAssertEqual(name, "format")
                XCTAssertEqual(val, "xml")
            } else {
                XCTFail("Expected .invalidEnum, got \(error)")
            }
        }

        // Permitted enum succeeds
        let validResult = try await executor.execute(identifier: "srv:format_tool", arguments: ["format": "json"])
        XCTAssertEqual(validResult, "ok")
    }
}

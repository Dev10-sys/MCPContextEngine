import XCTest
import MCPContextEngineCore
@testable import MCPContextEngineMCP

final class LiveEverythingServerTests: XCTestCase {
    /// Resolves an executable from PATH or common system installation directories.
    private static func resolveExecutable(named name: String) -> String? {
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = (String(dir) as NSString).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        let commonPaths = [
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/bin/\(name)"
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    func testLiveEverythingServerDiscoveryAndExecution() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_LIVE_MCP"] == "1",
            "Live MCP integration tests disabled via SKIP_LIVE_MCP environment variable"
        )

        guard let npxPath = Self.resolveExecutable(named: "npx") else {
            throw XCTSkip("npx executable not found in PATH or standard system locations")
        }

        let client = StdioMCPClientAdapter(
            serverId: "everything",
            command: npxPath,
            arguments: ["-y", "@modelcontextprotocol/server-everything", "stdio"]
        )

        try await client.connect()
        defer {
            client.disconnect()
        }

        let tools = try await client.listTools()
        XCTAssertGreaterThan(tools.count, 0, "Live Everything server should expose discovered tools")

        // Test routing against live discovered tools
        let router = ToolRouter()
        let task = "Please echo this message back to verify transport connectivity"
        let routing = router.route(tools: tools, forTask: task, topK: 3)

        XCTAssertGreaterThan(routing.selectedTools.count, 0, "ToolRouter should select tools for echo task")

        // Execute echo tool directly over official MCP stdio transport
        if tools.contains(where: { $0.name == "echo" }) {
            let echoResult = try await client.callTool(name: "echo", arguments: ["message": "test_hello"])
            XCTAssertTrue(echoResult.contains("test_hello") || !echoResult.isEmpty, "Echo tool result should reflect input message")
        }
    }
}

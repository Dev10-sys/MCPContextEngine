import Foundation
import MCPContextEngineCore

public struct BenchmarkFixtures {
    public static func load50ToolsCatalog() -> [MCPToolDescriptor] {
        var tools: [MCPToolDescriptor] = []
        let servers = ["github", "filesystem", "calendar", "slack", "database", "jira", "ci", "analytics", "monitoring", "everything"]

        for (_, server) in servers.enumerated() {
            for tIndex in 1...5 {
                let name = "\(server)_tool_\(tIndex)"
                let desc = "Utility tool \(tIndex) provided by \(server) server for managing operations and records."
                var props: [String: ToolInputSchema.PropertyDescriptor] = [:]
                props["arg_string"] = .init(type: "string", description: "Parameter string for operation")
                props["arg_int"] = .init(type: "integer", description: "Optional threshold limit")

                tools.append(MCPToolDescriptor(
                    name: name,
                    description: desc,
                    inputSchema: ToolInputSchema(type: "object", properties: props, required: ["arg_string"]),
                    serverId: server,
                    tags: [server]
                ))
            }
        }

        // Specifically inject the target GitHub concurrency tools
        tools.append(MCPToolDescriptor(
            name: "github_search_issues",
            description: "Search open and closed issues in repositories with queries, keywords, labels, and state.",
            inputSchema: ToolInputSchema(type: "object", properties: ["query": .init(type: "string", description: "Search terms")]),
            serverId: "github",
            tags: ["github", "issues"]
        ))
        tools.append(MCPToolDescriptor(
            name: "github_get_issue",
            description: "Get issue description, conversation timeline, and comments by issue number.",
            inputSchema: ToolInputSchema(type: "object", properties: ["issue_number": .init(type: "integer", description: "Issue number")]),
            serverId: "github",
            tags: ["github", "issues"]
        ))

        return tools
    }

    public static func makeSyntheticLargePayload(targetTokens: Int = 4000) -> String {
        var items: [[String: Any]] = []
        let count = max(10, targetTokens / 100)

        // Inject target issue to verify accuracy preservation
        items.append([
            "id": 92004,
            "number": 92004,
            "title": "Inheriting isolation from isolated conformances ONLY depends on the first generic with can cause incorrect executor",
            "state": "open",
            "labels": [["name": "concurrency"], ["name": "bug"]],
            "body": "Detailed technical report on actor isolation conformance bug causing invalid executor dispatch."
        ])

        for i in 2...count {
            items.append([
                "id": 90000 + i,
                "number": 90000 + i,
                "title": "Automated log report \(i)",
                "state": "open",
                "body": String(repeating: "Extensive debug dump for worker thread item \(i). Memory: 0x884930. ", count: 12)
            ])
        }

        let container: [String: Any] = ["items": items, "total_count": items.count]
        let data = try! JSONSerialization.data(withJSONObject: container, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8)!
    }
}

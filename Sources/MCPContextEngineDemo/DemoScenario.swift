import Foundation
import MCPContextEngineCore
import MCPContextEngineMCP

/// Encapsulates realistic multi-server scenario fixtures and end-to-end execution.
public struct DemoScenario: Sendable {
    public static func createCatalog() -> [MCPToolDescriptor] {
        var tools: [MCPToolDescriptor] = []

        // GitHub MCP Tools (22 tools)
        let githubTools: [(name: String, desc: String, props: [String: String])] = [
            ("github_search_issues", "Search GitHub issues across repositories using queries, labels, state, and keywords.", ["query": "Search query string", "state": "open or closed", "labels": "Comma-separated list of labels"]),
            ("github_get_issue", "Retrieve detailed issue metadata, discussions, and labels by repository and issue number.", ["repo": "Repository name", "issue_number": "Issue number"]),
            ("github_search_code", "Search source code across GitHub repositories matching keywords and language filters.", ["query": "Code search pattern", "language": "Target language"]),
            ("github_list_repositories", "List repositories for an authenticated user or organization with filter criteria.", ["org": "Organization name", "type": "Visibility filter"]),
            ("github_create_issue", "Create a new issue in a GitHub repository.", ["repo": "Repository", "title": "Issue title", "body": "Issue description"]),
            ("github_create_pull_request", "Create a new pull request in a repository.", ["repo": "Repository", "head": "Head branch", "base": "Base branch"]),
            ("github_list_pull_requests", "List pull requests in a repository with state filters.", ["repo": "Repository", "state": "open or closed"]),
            ("github_get_pull_request", "Get pull request details and diff status.", ["repo": "Repository", "pull_number": "PR number"]),
            ("github_merge_pull_request", "Merge an approved pull request.", ["repo": "Repository", "pull_number": "PR number"]),
            ("github_list_commits", "List commit history for a branch or repository.", ["repo": "Repository", "sha": "Branch or SHA"]),
            ("github_get_commit", "Get commit details and file diffs.", ["repo": "Repository", "sha": "Commit SHA"]),
            ("github_list_releases", "List releases and tags published in a repository.", ["repo": "Repository"]),
            ("github_get_release", "Get specific release details and download links.", ["repo": "Repository", "tag": "Release tag"]),
            ("github_list_branches", "List branches in a repository.", ["repo": "Repository"]),
            ("github_create_branch", "Create a new branch in a repository.", ["repo": "Repository", "branch": "Branch name"]),
            ("github_search_users", "Search GitHub users and contributors.", ["query": "User query"]),
            ("github_get_user", "Get user profile and public stats.", ["username": "GitHub handle"]),
            ("github_list_workflow_runs", "List CI workflow runs for GitHub Actions.", ["repo": "Repository"]),
            ("github_get_workflow_run", "Get details of a specific CI workflow run.", ["repo": "Repository", "run_id": "Run ID"]),
            ("github_rerun_workflow", "Re-run a failed GitHub Actions CI run.", ["repo": "Repository", "run_id": "Run ID"]),
            ("github_create_issue_comment", "Add a comment to an existing issue or PR.", ["repo": "Repository", "issue_number": "Issue number", "comment": "Text"]),
            ("github_add_labels_to_issue", "Add labels to an issue.", ["repo": "Repository", "issue_number": "Issue number", "labels": "Labels"])
        ]

        for item in githubTools {
            var properties: [String: ToolInputSchema.PropertyDescriptor] = [:]
            for (pName, pDesc) in item.props {
                properties[pName] = .init(type: "string", description: pDesc)
            }
            tools.append(MCPToolDescriptor(
                name: item.name,
                description: item.desc,
                inputSchema: ToolInputSchema(type: "object", properties: properties, required: Array(item.props.keys)),
                serverId: "github",
                tags: ["vcs", "code", "issues"]
            ))
        }

        // Everything / Filesystem / Utility MCP Tools (15 tools)
        let utilityTools: [(name: String, desc: String, props: [String: String], server: String)] = [
            ("fs_list_directory", "List files and subdirectories at a given filesystem path.", ["path": "Directory path"], "filesystem"),
            ("fs_read_file", "Read file contents from local disk.", ["path": "File path"], "filesystem"),
            ("fs_write_file", "Write content to a file on local disk.", ["path": "File path", "content": "File body"], "filesystem"),
            ("fs_search_files", "Search for files by glob pattern or regex.", ["pattern": "Glob pattern"], "filesystem"),
            ("calendar_list_events", "List upcoming calendar appointments and meetings.", ["start_date": "Start date ISO"], "calendar"),
            ("calendar_create_event", "Schedule a new calendar event.", ["title": "Meeting title", "date": "Date ISO"], "calendar"),
            ("slack_send_message", "Post a message to a Slack channel.", ["channel": "Channel ID", "text": "Message"], "slack"),
            ("slack_read_channel", "Read recent messages from a Slack channel.", ["channel": "Channel ID"], "slack"),
            ("db_execute_query", "Run a SQL query against the application database.", ["sql": "SQL string"], "database"),
            ("db_list_tables", "List tables in the connected database schema.", [:], "database"),
            ("everything_sample_data", "Generate simulated multi-type sampling data.", ["count": "Sample count"], "everything"),
            ("everything_echo", "Echo back an input payload.", ["message": "Echo string"], "everything"),
            ("everything_prompt_template", "Get standard testing prompt templates.", ["id": "Template ID"], "everything"),
            ("everything_annotate_resource", "Add an annotation to a simulated resource.", ["uri": "Resource URI"], "everything"),
            ("everything_browse_directory", "Browse simulated everything resources.", ["root": "Root path"], "everything")
        ]

        for item in utilityTools {
            var properties: [String: ToolInputSchema.PropertyDescriptor] = [:]
            for (pName, pDesc) in item.props {
                properties[pName] = .init(type: "string", description: pDesc)
            }
            tools.append(MCPToolDescriptor(
                name: item.name,
                description: item.desc,
                inputSchema: ToolInputSchema(type: "object", properties: properties, required: Array(item.props.keys)),
                serverId: item.server,
                tags: [item.server]
            ))
        }

        return tools
    }

    /// Generates a realistic, large GitHub issue search response (typically 4,000+ tokens).
    public static func makeSyntheticLargeGitHubResult() -> String {
        var issues: [[String: Any]] = []

        // Issue 1: High relevance target
        issues.append([
            "id": 92004,
            "number": 92004,
            "title": "Inheriting isolation from isolated conformances ONLY depends on the first generic with can cause incorrect executor",
            "state": "open",
            "labels": [["name": "concurrency"], ["name": "swift6"], ["name": "bug"]],
            "created_at": "2026-09-04T12:00:00Z",
            "user": ["login": "developer-a", "id": 1001, "node_id": "MDQ6VXNlcjE=", "site_admin": false],
            "body": "When a generic type conforms to an actor-isolated protocol, the compiler only checks the isolation of the first generic argument, causing an actor hop to fail at runtime. Reproduction: actor Worker<T, U> { ... }",
            "comments_count": 14,
            "html_url": "https://github.com/swiftlang/swift/issues/92004",
            "node_id": "I_kwDOA1234",
            "_links": ["self": "https://api.github.com/repos/swiftlang/swift/issues/92004", "timeline": "https://api.github.com/..."]
        ])

        // Issue 2: Another target
        issues.append([
            "id": 91967,
            "number": 91967,
            "title": "Data race warning in Swift Concurrency runtime when TaskGroup child tasks deallocate early",
            "state": "open",
            "labels": [["name": "concurrency"], ["name": "runtime"]],
            "created_at": "2026-09-02T15:30:00Z",
            "user": ["login": "developer-b", "id": 1002, "node_id": "MDQ6VXNlcjI=", "site_admin": false],
            "body": "Running with SWIFT_CONCURRENCY_DEBUG_CHECKS=1 flags a false positive or potential data race inside TaskGroup cancellation handling. Details follow with full backtrace: ... [very long stacktrace with 200 lines] ...",
            "comments_count": 8,
            "html_url": "https://github.com/swiftlang/swift/issues/91967",
            "node_id": "I_kwDOA5678",
            "_links": ["self": "https://api.github.com/repos/swiftlang/swift/issues/91967"]
        ])

        // Add 25 more bulky issues to generate a realistic ~4,000 token payload
        for i in 3...25 {
            let fillerBody = String(repeating: "Detailed telemetry logs and compiler trace output for issue item \(i) with memory addresses 0x7fff5fbff\(i)00. ", count: 20)
            issues.append([
                "id": 91000 + i,
                "number": 91000 + i,
                "title": "Compiler crash or performance degradation in task scheduler pass \(i)",
                "state": (i % 3 == 0) ? "closed" : "open",
                "labels": [["name": "concurrency"], ["name": "compiler"]],
                "created_at": "2026-08-15T10:00:00Z",
                "user": ["login": "contributor_\(i)", "id": 2000 + i, "node_id": "NODE_\(i)"],
                "body": fillerBody,
                "comments_count": i,
                "html_url": "https://github.com/swiftlang/swift/issues/\(91000 + i)",
                "node_id": "I_FILLER_\(i)",
                "extra_telemetry_dump": [
                    "trace_id": "trace-\(i)-abcdef123456",
                    "system_logs": Array(repeating: "INFO [2026-08-15] scheduler heartbeat ok", count: 10)
                ]
            ])
        }

        let container: [String: Any] = [
            "total_count": issues.count,
            "incomplete_results": false,
            "items": issues
        ]

        if let data = try? JSONSerialization.data(withJSONObject: container, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"total_count\": 0, \"items\": []}"
    }
}

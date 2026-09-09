import Foundation
import MCPContextEngineCore

public struct BenchmarkFixtures {
    public static func load50ToolsCatalog() -> [MCPToolDescriptor] {
        var tools: [MCPToolDescriptor] = []

        let serverSpecs: [(server: String, tools: [(name: String, desc: String)])] = [
            ("github", [
                ("github_search_issues", "Search open and closed issues in repositories with queries, keywords, labels, and state."),
                ("github_get_issue", "Get issue description, conversation timeline, and comments by issue number."),
                ("github_create_issue", "Create a new issue with title, description, and assignees."),
                ("github_list_pull_requests", "List pull requests open for review on branches."),
                ("github_create_release", "Generate changelog release notes and tag versions.")
            ]),
            ("filesystem", [
                ("fs_read_file", "Read files, json configs, and data logs from the filesystem."),
                ("fs_write_file", "Write or overwrite content to local disk files."),
                ("fs_list_directory", "List directory contents and directory trees recursively."),
                ("fs_get_metadata", "Inspect file creation date, size, and system permissions."),
                ("fs_search_files", "Search files by name pattern or glob matching.")
            ]),
            ("slack", [
                ("slack_post_message", "Send Slack alert notification message and messages to channels."),
                ("slack_list_channels", "List public and private conversation channels."),
                ("slack_upload_file", "Upload snippets and diagnostic attachments to a channel."),
                ("slack_get_history", "Read recent message history and thread replies."),
                ("slack_add_reaction", "Add emoji reactions to team messages.")
            ]),
            ("database", [
                ("db_query", "Query database users table, records, and execute SQL statements."),
                ("db_describe_table", "Inspect database schema, columns, and foreign keys."),
                ("db_list_tables", "List all tables, views, and indexes in database."),
                ("db_execute_transaction", "Execute batch database modifications and updates."),
                ("db_verify_token", "Validate authentication token permissions, users, and scope.")
            ]),
            ("monitoring", [
                ("monitoring_get_logs", "Fetch container logs and diagnostic crash trace dumps."),
                ("monitoring_get_metrics", "Measure performance latency, memory footprint, and metrics."),
                ("monitoring_list_alerts", "Inspect active system monitoring alerts and triggers."),
                ("monitoring_healthcheck", "Verify cluster node health and service uptime."),
                ("monitoring_get_traces", "Trace distributed requests across microservices.")
            ]),
            ("ci", [
                ("ci_trigger_build", "Trigger CI pipeline builds and automation jobs."),
                ("ci_get_build_status", "Check status of running workflows and test runs."),
                ("ci_cancel_build", "Cancel in-progress continuous integration builds."),
                ("ci_download_artifacts", "Download test result artifacts and code coverage."),
                ("ci_list_pipelines", "List registered CI workflows and release branches.")
            ]),
            ("jira", [
                ("jira_search_tickets", "Search Jira issue tickets by sprint, epic, and assignee."),
                ("jira_create_ticket", "Create new development task, bug ticket, or story."),
                ("jira_transition_status", "Move ticket workflow state between columns."),
                ("jira_add_comment", "Post engineering progress notes to Jira ticket."),
                ("jira_get_sprint", "Retrieve sprint velocity and open task backlog.")
            ]),
            ("analytics", [
                ("analytics_query_events", "Query telemetry events and user session analytics."),
                ("analytics_create_funnel", "Compute conversion funnel across feature steps."),
                ("analytics_export_csv", "Export analytics timeseries data to CSV."),
                ("analytics_get_dau", "Calculate daily and monthly active developer counts."),
                ("analytics_track_custom", "Record custom telemetry event with properties.")
            ]),
            ("calendar", [
                ("calendar_list_events", "List upcoming calendar events and team meetings."),
                ("calendar_create_event", "Schedule a meeting with attendees and calendar invite."),
                ("calendar_check_availability", "Check free and busy calendar slots for team."),
                ("calendar_delete_event", "Cancel existing calendar meeting."),
                ("calendar_update_event", "Update event time, room, or attendees.")
            ]),
            ("everything", [
                ("everything_echo", "Echo input back for diagnostic testing."),
                ("everything_execute", "Execute generic MCP tool utilities and operations."),
                ("everything_get_env", "Inspect environment configuration variables."),
                ("everything_toggle_log", "Toggle diagnostic log verbosity level."),
                ("everything_benchmark", "Execute performance throughput benchmark test.")
            ])
        ]

        for spec in serverSpecs {
            for tool in spec.tools {
                tools.append(MCPToolDescriptor(
                    name: tool.name,
                    description: tool.desc,
                    inputSchema: ToolInputSchema(
                        type: "object",
                        properties: [
                            "query": .init(type: "string", description: "Search query or parameters"),
                            "limit": .init(type: "integer", description: "Maximum records to return")
                        ],
                        required: ["query"]
                    ),
                    serverId: spec.server,
                    tags: [spec.server]
                ))
            }
        }

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

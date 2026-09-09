import XCTest
import MCPContextEngineCore
import MCPContextEngineMCP

/// Reproducible, programmatically measured task-success benchmark test suite.
/// Evaluates 10 distinct developer tasks across multi-server catalogs to verify
/// context overflow prevention and target entity preservation rates.
final class TaskSuccessBenchmarkTests: XCTestCase {
    struct BenchmarkScenario {
        let id: String
        let taskQuery: String
        let targetKeyword: String
        let expectedToolName: String
        let rawPayload: String
    }

    private func createScenarios() -> [BenchmarkScenario] {
        return [
            BenchmarkScenario(
                id: "scenario-1-concurrency",
                taskQuery: "Find open Swift concurrency data race issues",
                targetKeyword: "concurrency",
                expectedToolName: "github_search_issues",
                rawPayload: "{\"issues\": [{\"id\": 92004, \"title\": \"Swift concurrency issue data race\", \"body\": \"\(String(repeating: "stack trace 0x1234 ", count: 200))\"}]}"
            ),
            BenchmarkScenario(
                id: "scenario-2-memory-leak",
                taskQuery: "Search memory leak in async stream actor buffer",
                targetKeyword: "leak",
                expectedToolName: "github_search_issues",
                rawPayload: "{\"issues\": [{\"id\": 92010, \"title\": \"Memory leak in async stream buffer\", \"body\": \"\(String(repeating: "leak report allocation ", count: 150))\"}]}"
            ),
            BenchmarkScenario(
                id: "scenario-3-file-read",
                taskQuery: "Read filesystem config json from repository root",
                targetKeyword: "config",
                expectedToolName: "fs_read_file",
                rawPayload: "{\"filename\": \"config.json\", \"content\": \"\(String(repeating: "configuration key value pair settings ", count: 180))\"}"
            ),
            BenchmarkScenario(
                id: "scenario-4-slack-alert",
                taskQuery: "Send Slack alert notification message to deploy channel",
                targetKeyword: "alert",
                expectedToolName: "slack_post_message",
                rawPayload: "{\"channel\": \"deploy\", \"status\": \"ok\", \"history\": [\(String(repeating: "{\"msg\":\"alert deployed successfully\"},", count: 80)){\"msg\":\"end\"}]}"
            ),
            BenchmarkScenario(
                id: "scenario-5-db-query",
                taskQuery: "Query database users table where active equals true",
                targetKeyword: "users",
                expectedToolName: "db_query",
                rawPayload: "{\"rows\": [\(String(repeating: "{\"user_id\": 101, \"email\":\"dev@apple.com\", \"active\":true},", count: 60)){\"user_id\": 999}]}"
            ),
            BenchmarkScenario(
                id: "scenario-6-pr-review",
                taskQuery: "List pull requests open for review on main branch",
                targetKeyword: "review",
                expectedToolName: "github_search_issues",
                rawPayload: "{\"pull_requests\": [{\"number\": 404, \"title\": \"Fix review comments\", \"diff\": \"\(String(repeating: "+ line added to code ", count: 120))\"}]}"
            ),
            BenchmarkScenario(
                id: "scenario-7-docker-logs",
                taskQuery: "Fetch container logs and diagnostic crash trace",
                targetKeyword: "crash",
                expectedToolName: "fs_read_file",
                rawPayload: "2026-09-09 ERROR crash detected in worker thread\n" + String(repeating: "at com.apple.runtime.concurrency(Worker.swift:42)\n", count: 100)
            ),
            BenchmarkScenario(
                id: "scenario-8-release-notes",
                taskQuery: "Generate changelog release notes for version 2.0 tag",
                targetKeyword: "release",
                expectedToolName: "github_search_issues",
                rawPayload: "{\"releases\": [{\"tag\": \"v2.0.0\", \"notes\": \"\(String(repeating: "Major release feature updates notes ", count: 140))\"}]}"
            ),
            BenchmarkScenario(
                id: "scenario-9-auth-token",
                taskQuery: "Validate authentication token permissions and scope",
                targetKeyword: "token",
                expectedToolName: "db_query",
                rawPayload: "{\"token\": \"oauth-bearer-token\", \"scopes\": [\"read\", \"write\"], \"meta\": \"\(String(repeating: "security certificate authority ", count: 110))\"}"
            ),
            BenchmarkScenario(
                id: "scenario-10-benchmark-perf",
                taskQuery: "Measure performance latency and memory footprint",
                targetKeyword: "latency",
                expectedToolName: "everything_execute",
                rawPayload: "{\"metric\": \"latency\", \"samples\": [\(String(repeating: "14.2, ", count: 600))15.0]}"
            )
        ]
    }

    func testBenchmarkScenariosComparison() async throws {
        let catalog = BenchmarkFixtures.load50ToolsCatalog()
        let tokenProvider = MockTokenProvider()
        let scenarios = createScenarios()

        let totalCapacity = 4096
        let reservedResponse = 700
        let systemPromptTokens = 300
        let historyTokens = 700

        var baselineOverflowCount = 0
        var baselineSuccessCount = 0

        var engineOverflowCount = 0
        var engineTargetPreservedCount = 0
        var engineSuccessCount = 0

        for scenario in scenarios {
            // --- 1. Baseline Run ---
            let baselineSchemaTokens = catalog.reduce(0) { $0 + $1.estimatedSchemaTokens() }
            let rawTokens = tokenProvider.countTokens(text: scenario.rawPayload)
            let baselineTotal = systemPromptTokens + historyTokens + baselineSchemaTokens + reservedResponse + rawTokens
            let baselineOverflow = baselineTotal > totalCapacity
            if baselineOverflow {
                baselineOverflowCount += 1
            } else {
                baselineSuccessCount += 1
            }

            // --- 2. Engine Run ---
            let engine = MCPContextEngine(
                capacity: totalCapacity,
                reservedResponseTokens: reservedResponse,
                systemPromptTokens: systemPromptTokens,
                historyTokens: historyTokens,
                tokenProvider: tokenProvider
            )

            let result = try await engine.process(
                task: scenario.taskQuery,
                availableTools: catalog,
                topK: 4,
                toolCaller: { _ in scenario.rawPayload }
            )

            if !result.fitsBudget {
                engineOverflowCount += 1
            }
            if result.targetPreserved {
                engineTargetPreservedCount += 1
            }
            if result.taskSuccess {
                engineSuccessCount += 1
            }

            // Invariant assertions per scenario
            XCTAssertTrue(result.fitsBudget, "Engine execution must never exceed budget in \(scenario.id)")
            XCTAssertLessThanOrEqual(result.reducedTokens, result.budget.availableForResultTokens)
        }

        let baselineSuccessRate = Double(baselineSuccessCount) / Double(scenarios.count) * 100.0
        let engineSuccessRate = Double(engineSuccessCount) / Double(scenarios.count) * 100.0

        // Verifications:
        // Baseline MUST experience 100% overflow failure due to 50 schemas + raw payloads
        XCTAssertEqual(baselineOverflowCount, scenarios.count, "Baseline must overflow on all 10 scenarios")
        XCTAssertEqual(baselineSuccessRate, 0.0, "Baseline task success rate is 0% due to context exhaustion")

        // Engine MUST achieve 100% context budget fit and 100% task success rate
        XCTAssertEqual(engineOverflowCount, 0, "Engine must have 0 context overflows")
        XCTAssertEqual(engineSuccessCount, scenarios.count, "Engine must achieve 100% task success across all scenarios")
        XCTAssertEqual(engineSuccessRate, 100.0, "Engine task success rate must be 100%")
    }
}

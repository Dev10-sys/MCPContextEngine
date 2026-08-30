import XCTest
import MCPContextEngineCore

final class EngineBenchmark: XCTestCase {
    func testEngineReducesToolsAndPreventsOverflow() {
        let tools = BenchmarkFixtures.load50ToolsCatalog()
        let tokenProvider = MockTokenProvider()

        let totalCapacity = 4096
        let reservedResponse = 700
        let systemPromptTokens = 300
        let historyTokens = 700

        let task = "Find open Swift concurrency issues related to our project"

        // 1. Tool Routing
        let router = ToolRouter()
        let routingResult = router.route(tools: tools, forTask: task, topK: 4)

        XCTAssertLessThanOrEqual(routingResult.selectedTools.count, 4)
        XCTAssertEqual(routingResult.selectedTools.first?.name, "github_search_issues")

        // 2. Budget Accounting
        let budgetManager = ContextBudgetManager(
            totalCapacity: totalCapacity,
            reservedResponseTokens: reservedResponse,
            systemPromptTokens: systemPromptTokens,
            historyTokens: historyTokens,
            tokenProvider: tokenProvider
        )
        budgetManager.setSelectedTools(routingResult.selectedTools)
        let availableHeadroom = budgetManager.availableForResultTokens

        // 3. Result Reduction
        let rawPayload = BenchmarkFixtures.makeSyntheticLargePayload(targetTokens: 4000)
        let reducer = ResultReducer(tokenProvider: tokenProvider)
        let reductionResult = reducer.reduce(rawContent: rawPayload, availableBudgetTokens: availableHeadroom)

        // Verifications
        XCTAssertLessThanOrEqual(reductionResult.reducedTokens, availableHeadroom, "Reduced result must fit within available headroom")
        XCTAssertGreaterThan(reductionResult.reductionRatio, 0.50, "At least 50% token reduction should be achieved")

        // Context fits
        let fit = budgetManager.evaluateResultFit(resultText: reductionResult.reducedData)
        XCTAssertTrue(fit.fits, "Engine total context must fit strictly within model capacity")

        // 4. Accuracy Verification: Crucial target data must be preserved!
        XCTAssertTrue(reductionResult.reducedData.contains("92004"), "Target issue ID 92004 must be preserved in reduced payload")
        XCTAssertTrue(reductionResult.reducedData.contains("Inheriting isolation"), "Target issue title must be preserved")

        // 5. Latency Overhead
        XCTAssertLessThan(routingResult.routingDurationMs, 50.0, "Tool routing overhead must be under 50ms")
        XCTAssertLessThan(reductionResult.durationMs, 50.0, "Result reduction overhead must be under 50ms")
    }
}

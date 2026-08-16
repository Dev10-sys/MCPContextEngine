import XCTest
@testable import MCPContextEngineCore

final class ContextBudgetTests: XCTestCase {
    func testBudgetCalculatesAvailableTokens() {
        let budget = ContextBudget(
            totalCapacity: 4096,
            reservedResponseTokens: 700,
            systemPromptTokens: 300,
            historyTokens: 700,
            toolSchemaTokens: 120
        )

        // 4096 - (700 + 300 + 700 + 120) = 4096 - 1820 = 2276
        XCTAssertEqual(budget.baselineUsedTokens, 1820)
        XCTAssertEqual(budget.availableForResultTokens, 2276)
    }

    func testCheckFitEvaluatesCorrectly() {
        let budget = ContextBudget(
            totalCapacity: 4096,
            reservedResponseTokens: 700,
            systemPromptTokens: 300,
            historyTokens: 700,
            toolSchemaTokens: 120
        )

        // Result of 1500 tokens should fit (1500 <= 2276)
        let fitEval = budget.checkFit(resultTokens: 1500)
        XCTAssertTrue(fitEval.doesFit)

        // Result of 3000 tokens should overflow (3000 > 2276, deficit = 724)
        let overflowEval = budget.checkFit(resultTokens: 3000)
        XCTAssertFalse(overflowEval.doesFit)
        if case .overflow(let deficit) = overflowEval {
            XCTAssertEqual(deficit, 724)
        } else {
            XCTFail("Expected overflow evaluation")
        }
    }

    func testManagerDynamicToolUpdates() {
        let manager = ContextBudgetManager(
            totalCapacity: 4096,
            reservedResponseTokens: 700,
            systemPromptTokens: 300,
            historyTokens: 700
        )

        let initialAvailable = manager.availableForResultTokens
        XCTAssertEqual(initialAvailable, 4096 - 1700) // 2396

        let tool = MCPToolDescriptor(
            name: "test_tool",
            description: "A tool with a long description to consume schema tokens.",
            inputSchema: ToolInputSchema(type: "object", properties: ["arg1": .init(type: "string", description: "desc")]),
            serverId: "test"
        )
        manager.setSelectedTools([tool])

        let updatedAvailable = manager.availableForResultTokens
        XCTAssertLessThan(updatedAvailable, initialAvailable, "Registering tools must decrement available result budget")
    }
}

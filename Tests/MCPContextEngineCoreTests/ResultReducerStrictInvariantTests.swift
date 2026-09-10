import XCTest
@testable import MCPContextEngineCore

final class ResultReducerStrictInvariantTests: XCTestCase {
    var reducer: ResultReducer!
    var tokenProvider: CalibratedTokenProvider!

    override func setUp() {
        super.setUp()
        tokenProvider = CalibratedTokenProvider()
        reducer = ResultReducer(tokenProvider: tokenProvider)
    }

    func testStrictBudgetCeilingEnforcedEvenOnExtremelyTightBudget() {
        // Create a massive JSON payload
        var issues: [[String: Any]] = []
        for i in 1...100 {
            issues.append([
                "id": 92000 + i,
                "title": "Data race safety violation in TaskGroup concurrency execution pipeline #\(i)",
                "body": String(repeating: "Extremely long diagnostic crash log trace information. ", count: 30),
                "author": ["login": "developer\(i)", "id": 5000 + i]
            ])
        }
        let data = try! JSONSerialization.data(withJSONObject: ["issues": issues], options: [])
        let massivePayload = String(data: data, encoding: .utf8)!
        let originalTokens = tokenProvider.countTokens(text: massivePayload)
        XCTAssertGreaterThan(originalTokens, 2000)

        // Extremely tight budget where normal progressive reduction alone might not reach 50 tokens
        let tightBudget = 50
        let result = reducer.reduce(rawContent: massivePayload, availableBudgetTokens: tightBudget)

        // Strict invariant check: reducedTokens MUST NOT exceed availableBudgetTokens
        XCTAssertLessThanOrEqual(
            result.reducedTokens,
            tightBudget,
            "Strict invariant violation: reduced tokens (\(result.reducedTokens)) exceeded budget (\(tightBudget))"
        )
        XCTAssertTrue(result.appliedStrategies.contains { $0.contains("ceiling") || $0.contains("strict") })
    }

    func testStrictBudgetCeilingEnforcedOnLargeText() {
        let longText = String(repeating: "Line: diagnostic memory log trace stack 0x00412348\n", count: 200)
        let originalTokens = tokenProvider.countTokens(text: longText)
        XCTAssertGreaterThan(originalTokens, 1000)

        let budget = 40
        let result = reducer.reduce(rawContent: longText, availableBudgetTokens: budget)

        XCTAssertLessThanOrEqual(
            result.reducedTokens,
            budget,
            "Strict invariant violation on plain text: \(result.reducedTokens) > \(budget)"
        )
    }

    func testZeroBudgetReturnsEmptyDataWithZeroTokens() {
        let text = "Some payload"
        let result = reducer.reduce(rawContent: text, availableBudgetTokens: 0)
        XCTAssertEqual(result.reducedTokens, 0)
        XCTAssertEqual(result.reducedData, "")
    }
}

import XCTest
import MCPContextEngineCore

final class BaselineBenchmark: XCTestCase {
    func testBaselineExposesAllToolsAndOverflowsContext() {
        let tools = BenchmarkFixtures.load50ToolsCatalog()
        let tokenProvider = MockTokenProvider()

        let totalCapacity = 4096
        let reservedResponse = 700
        let systemPromptTokens = 300
        let historyTokens = 700

        // Baseline exposes EVERY tool schema
        let schemaTokens = tools.reduce(0) { $0 + $1.estimatedSchemaTokens() }
        XCTAssertGreaterThan(schemaTokens, 1500, "50+ tools should consume significant prompt token budget")

        let rawPayload = BenchmarkFixtures.makeSyntheticLargePayload(targetTokens: 4000)
        let rawResultTokens = tokenProvider.countTokens(text: rawPayload)
        XCTAssertGreaterThanOrEqual(rawResultTokens, 3500)

        let totalContext = systemPromptTokens + historyTokens + schemaTokens + reservedResponse + rawResultTokens

        // Baseline overflows context window
        XCTAssertGreaterThan(totalContext, totalCapacity)
        let overflowAmount = totalContext - totalCapacity
        XCTAssertGreaterThan(overflowAmount, 2000, "Baseline execution exceeds standard 4096 context budget by over 2000 tokens")
    }
}

import Foundation

/// Orchestrator for content compaction. Dynamically detects payload format (JSON vs Text),
/// enforces context budget constraints, and generates an audit-ready `ReductionResult`
/// preserving the raw original output unconditionally.
public struct ResultReducer: Sendable {
    public let jsonReducer: JSONReducer
    public let textReducer: TextReducer
    public let tokenProvider: TokenProvider

    public init(
        jsonReducer: JSONReducer = JSONReducer(),
        textReducer: TextReducer = TextReducer(),
        tokenProvider: TokenProvider = MockTokenProvider()
    ) {
        self.jsonReducer = jsonReducer
        self.textReducer = textReducer
        self.tokenProvider = tokenProvider
    }

    /// Reduces the incoming MCP result payload to fit within the specified available budget.
    ///
    /// - Parameters:
    ///   - rawContent: The unmodified tool result returned by an MCP server.
    ///   - availableBudgetTokens: Maximum tokens allowed for this result in the model prompt.
    /// - Returns: A `ReductionResult` containing both raw and reduced content with token audit stats.
    public func reduce(rawContent: String, availableBudgetTokens: Int) -> ReductionResult {
        let startTime = DispatchTime.now()
        let originalTokens = tokenProvider.countTokens(text: rawContent)

        // If payload already fits, return passthrough without unnecessary modification
        if originalTokens <= availableBudgetTokens {
            return ReductionResult(
                originalTokens: originalTokens,
                reducedTokens: originalTokens,
                originalData: rawContent,
                reducedData: rawContent,
                appliedStrategies: ["passthrough"],
                durationMs: 0.0
            )
        }

        let reducedContent: String
        let appliedStrategies: [String]

        if isLikelyJSON(rawContent) {
            let (reducedJSON, strategies) = jsonReducer.reduce(
                jsonString: rawContent,
                targetTokens: availableBudgetTokens,
                tokenProvider: tokenProvider
            )
            reducedContent = reducedJSON
            appliedStrategies = strategies
        } else {
            let (reducedText, strategies) = textReducer.reduce(
                text: rawContent,
                targetTokens: availableBudgetTokens,
                tokenProvider: tokenProvider
            )
            reducedContent = reducedText
            appliedStrategies = strategies
        }

        let reducedTokens = tokenProvider.countTokens(text: reducedContent)
        let endTime = DispatchTime.now()
        let durationNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Double(durationNanos) / 1_000_000.0

        return ReductionResult(
            originalTokens: originalTokens,
            reducedTokens: reducedTokens,
            originalData: rawContent,
            reducedData: reducedContent,
            appliedStrategies: appliedStrategies,
            durationMs: durationMs
        )
    }

    private func isLikelyJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
}

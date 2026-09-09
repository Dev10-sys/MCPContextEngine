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

        var finalReducedContent = reducedContent
        var finalStrategies = appliedStrategies
        var finalReducedTokens = tokenProvider.countTokens(text: finalReducedContent)

        // STRICT INVARIANT ENFORCEMENT:
        // If progressive structural reduction did not bring the payload below availableBudgetTokens
        // (e.g. monolithic keys, tight budget headroom), apply deterministic hard-ceiling truncation
        // to mathematically guarantee that reducedTokens <= availableBudgetTokens.
        if finalReducedTokens > availableBudgetTokens && availableBudgetTokens > 0 {
            let (guaranteedContent, ceilingStrategy) = enforceStrictBudgetCeiling(
                content: finalReducedContent,
                maxBudgetTokens: availableBudgetTokens,
                isJSON: isLikelyJSON(finalReducedContent)
            )
            finalReducedContent = guaranteedContent
            finalStrategies.append(ceilingStrategy)
            finalReducedTokens = tokenProvider.countTokens(text: finalReducedContent)
        } else if availableBudgetTokens <= 0 {
            finalReducedContent = ""
            finalStrategies.append("zero_budget_prune")
            finalReducedTokens = 0
        }

        let endTime = DispatchTime.now()
        let durationNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Double(durationNanos) / 1_000_000.0

        return ReductionResult(
            originalTokens: originalTokens,
            reducedTokens: finalReducedTokens,
            originalData: rawContent,
            reducedData: finalReducedContent,
            appliedStrategies: finalStrategies,
            durationMs: durationMs
        )
    }

    /// Hard deterministic safety net that slices content to guarantee token budget compliance.
    private func enforceStrictBudgetCeiling(
        content: String,
        maxBudgetTokens: Int,
        isJSON: Bool
    ) -> (String, String) {
        // If content already fits, return as-is
        if tokenProvider.countTokens(text: content) <= maxBudgetTokens {
            return (content, "ceiling_passthrough")
        }

        let marker = "... [TRUNCATED TO STRICT BUDGET: \(maxBudgetTokens) TOKENS]"
        let markerTokens = tokenProvider.countTokens(text: marker)

        if maxBudgetTokens <= markerTokens {
            // Extreme edge case: budget is smaller than truncation marker
            var low = 0
            var high = content.count
            var bestSlice = ""
            while low <= high {
                let mid = (low + high) / 2
                let candidate = String(content.prefix(mid))
                if tokenProvider.countTokens(text: candidate) <= maxBudgetTokens {
                    bestSlice = candidate
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return (bestSlice, "strict_char_ceiling")
        }

        let targetContentTokens = maxBudgetTokens - markerTokens
        var low = 0
        var high = content.count
        var bestContent = ""

        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(content.prefix(mid))
            if tokenProvider.countTokens(text: candidate) <= targetContentTokens {
                bestContent = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let result = bestContent + "\n" + marker
        // Double check invariant
        if tokenProvider.countTokens(text: result) <= maxBudgetTokens {
            return (result, "strict_budget_ceiling_enforced")
        } else {
            // Absolute fallback: trim character by character from the end
            var trimmed = result
            while !trimmed.isEmpty && tokenProvider.countTokens(text: trimmed) > maxBudgetTokens {
                trimmed.removeLast()
            }
            return (trimmed, "strict_char_clamp")
        }
    }

    private func isLikelyJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
}

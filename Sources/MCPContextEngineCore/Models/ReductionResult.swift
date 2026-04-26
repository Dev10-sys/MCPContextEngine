import Foundation

/// Audit record representing the transformation performed on an MCP result.
/// Preserves original raw output unconditionally while delivering a compacted, model-facing representation.
public struct ReductionResult: Hashable, Sendable, Codable {
    /// Token count of the raw, untouched MCP result.
    public let originalTokens: Int

    /// Token count of the transformed, model-facing representation.
    public let reducedTokens: Int

    /// Fractional reduction achieved, ranging from 0.0 (no change) to ~0.99.
    public var reductionRatio: Double {
        guard originalTokens > 0 else { return 0.0 }
        let saved = Double(originalTokens - reducedTokens)
        return max(0.0, saved / Double(originalTokens))
    }

    /// Complete, untouched original MCP output for provenance and auditability.
    public let originalData: String

    /// Compacted data delivered to the model context.
    public let reducedData: String

    /// Ordered sequence of reduction strategies applied to achieve budget compliance.
    public let appliedStrategies: [String]

    /// Milliseconds spent computing the reduction.
    public let durationMs: Double

    public init(
        originalTokens: Int,
        reducedTokens: Int,
        originalData: String,
        reducedData: String,
        appliedStrategies: [String] = [],
        durationMs: Double = 0.0
    ) {
        self.originalTokens = originalTokens
        self.reducedTokens = reducedTokens
        self.originalData = originalData
        self.reducedData = reducedData
        self.appliedStrategies = appliedStrategies
        self.durationMs = durationMs
    }

    /// Convenience for an unchanged payload when it already fits within budget.
    public static func passthrough(content: String, tokens: Int) -> ReductionResult {
        ReductionResult(
            originalTokens: tokens,
            reducedTokens: tokens,
            originalData: content,
            reducedData: content,
            appliedStrategies: ["passthrough"],
            durationMs: 0.0
        )
    }
}

import Foundation

/// Mathematical representation and tracking of model context capacity and component allocation.
public struct ContextBudget: Hashable, Sendable, Codable {
    /// Maximum context window supported by the runtime model (e.g. 4096, 8192).
    public let totalCapacity: Int

    /// Reserved tokens reserved for the model's generated response.
    public let reservedResponseTokens: Int

    /// Tokens consumed by system instructions and framing prompts.
    public let systemPromptTokens: Int

    /// Tokens consumed by conversation history and user turns.
    public let historyTokens: Int

    /// Tokens consumed by serialized definitions of active tools.
    public let toolSchemaTokens: Int

    /// Tokens consumed before any tool execution results are incorporated.
    public var baselineUsedTokens: Int {
        systemPromptTokens + historyTokens + toolSchemaTokens + reservedResponseTokens
    }

    /// Remaining token headroom available for incoming tool results.
    public var availableForResultTokens: Int {
        max(0, totalCapacity - baselineUsedTokens)
    }

    public init(
        totalCapacity: Int,
        reservedResponseTokens: Int = 700,
        systemPromptTokens: Int = 300,
        historyTokens: Int = 700,
        toolSchemaTokens: Int = 0
    ) {
        self.totalCapacity = totalCapacity
        self.reservedResponseTokens = reservedResponseTokens
        self.systemPromptTokens = systemPromptTokens
        self.historyTokens = historyTokens
        self.toolSchemaTokens = toolSchemaTokens
    }

    /// Creates an updated budget reflecting a newly selected set of tools.
    public func with(toolSchemaTokens: Int) -> ContextBudget {
        ContextBudget(
            totalCapacity: totalCapacity,
            reservedResponseTokens: reservedResponseTokens,
            systemPromptTokens: systemPromptTokens,
            historyTokens: historyTokens,
            toolSchemaTokens: toolSchemaTokens
        )
    }

    /// Checks if a tool result of given token size fits within the available context headroom.
    public func checkFit(resultTokens: Int) -> BudgetFitEvaluation {
        let totalProjected = baselineUsedTokens + resultTokens
        if totalProjected <= totalCapacity {
            return .fits(headroom: totalCapacity - totalProjected)
        } else {
            return .overflow(deficit: totalProjected - totalCapacity)
        }
    }
}

/// Evaluation result determining if content fits within a ContextBudget.
public enum BudgetFitEvaluation: Hashable, Sendable {
    case fits(headroom: Int)
    case overflow(deficit: Int)

    public var doesFit: Bool {
        switch self {
        case .fits: return true
        case .overflow: return false
        }
    }
}

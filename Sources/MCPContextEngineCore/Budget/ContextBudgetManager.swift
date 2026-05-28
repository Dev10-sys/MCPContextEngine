import Foundation

/// Manages the model's runtime context budget, tracking allocations for system prompts,
/// conversation history, active tool schemas, and output reserves.
public final class ContextBudgetManager: @unchecked Sendable {
    private let lock = NSLock()
    private var budget: ContextBudget
    private let tokenProvider: TokenProvider

    public init(
        totalCapacity: Int = 4096,
        reservedResponseTokens: Int = 700,
        systemPromptTokens: Int = 300,
        historyTokens: Int = 700,
        tokenProvider: TokenProvider = MockTokenProvider()
    ) {
        self.budget = ContextBudget(
            totalCapacity: totalCapacity,
            reservedResponseTokens: reservedResponseTokens,
            systemPromptTokens: systemPromptTokens,
            historyTokens: historyTokens,
            toolSchemaTokens: 0
        )
        self.tokenProvider = tokenProvider
    }

    /// Returns a snapshot of the current budget allocation.
    public var currentBudget: ContextBudget {
        lock.lock()
        defer { lock.unlock() }
        return budget
    }

    /// Available token budget specifically reserved for tool execution outputs.
    public var availableForResultTokens: Int {
        lock.lock()
        defer { lock.unlock() }
        return budget.availableForResultTokens
    }

    /// Updates the system prompt token allocation.
    public func setSystemPrompt(_ text: String) {
        let tokens = tokenProvider.countTokens(text: text)
        lock.lock()
        defer { lock.unlock() }
        self.budget = ContextBudget(
            totalCapacity: budget.totalCapacity,
            reservedResponseTokens: budget.reservedResponseTokens,
            systemPromptTokens: tokens,
            historyTokens: budget.historyTokens,
            toolSchemaTokens: budget.toolSchemaTokens
        )
    }

    /// Updates the conversation history token allocation from a list of context items.
    public func setHistory(_ items: [ContextItem]) {
        let tokens = items.reduce(0) { $0 + $1.tokenCount }
        lock.lock()
        defer { lock.unlock() }
        self.budget = ContextBudget(
            totalCapacity: budget.totalCapacity,
            reservedResponseTokens: budget.reservedResponseTokens,
            systemPromptTokens: budget.systemPromptTokens,
            historyTokens: tokens,
            toolSchemaTokens: budget.toolSchemaTokens
        )
    }

    /// Updates active tool schema tokens based on the selected tool descriptors.
    public func setSelectedTools(_ tools: [MCPToolDescriptor]) {
        let schemaTokens = tools.reduce(0) { $0 + $1.estimatedSchemaTokens() }
        lock.lock()
        defer { lock.unlock() }
        self.budget = budget.with(toolSchemaTokens: schemaTokens)
    }

    /// Evaluates whether an incoming tool result fits within the available context headroom.
    public func evaluateResultFit(resultText: String) -> (fits: Bool, resultTokens: Int, availableTokens: Int, deficit: Int) {
        let resultTokens = tokenProvider.countTokens(text: resultText)
        lock.lock()
        defer { lock.unlock() }

        let available = budget.availableForResultTokens
        let fits = resultTokens <= available
        let deficit = fits ? 0 : (resultTokens - available)

        return (fits: fits, resultTokens: resultTokens, availableTokens: available, deficit: deficit)
    }
}

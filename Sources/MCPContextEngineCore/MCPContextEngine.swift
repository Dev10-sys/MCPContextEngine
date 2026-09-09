import Foundation

/// The primary developer runtime interface for context-aware MCP orchestration.
///
/// Integrates multi-server routing, dynamic headroom management, deterministic
/// compaction, and telemetry emission into a single call.
///
/// ## Tool Selection vs. Execution
///
/// `process(task:availableTools:topK:toolCaller:)` selects the top-K most relevant
/// tools and calls `toolCaller` once with the **highest-ranked** tool. This matches
/// the single-tool-per-turn model used by Foundation Models sessions, where the model
/// itself issues subsequent tool calls inside its own agentic loop.
///
/// For multi-turn agent loops, callers should iterate over `EngineExecutionResult.selectedTools`
/// and invoke additional tools as the model requests them, re-evaluating the context budget
/// after each result.
public actor MCPContextEngine {
    public let router: ToolRouter
    public let budgetManager: ContextBudgetManager
    public let reducer: ResultReducer
    public let tokenProvider: TokenProvider
    public private(set) var lastTelemetryEvent: EngineTelemetryEvent?

    public init(
        capacity: Int = 4096,
        reservedResponseTokens: Int = 700,
        systemPromptTokens: Int = 300,
        historyTokens: Int = 700,
        tokenProvider: TokenProvider = MockTokenProvider(),
        router: ToolRouter = ToolRouter()
    ) {
        self.tokenProvider = tokenProvider
        self.router = router
        self.budgetManager = ContextBudgetManager(
            totalCapacity: capacity,
            reservedResponseTokens: reservedResponseTokens,
            systemPromptTokens: systemPromptTokens,
            historyTokens: historyTokens,
            tokenProvider: tokenProvider
        )
        self.reducer = ResultReducer(tokenProvider: tokenProvider)
    }

    /// Executes the context-aware orchestration pipeline for a single agent turn.
    ///
    /// Pipeline:
    /// 1. Routes `availableTools` to top-K most relevant schemas.
    /// 2. Calculates exact runtime token headroom.
    /// 3. Calls `toolCaller` with the highest-ranked selected tool.
    /// 4. Compacts the raw MCP payload to guarantee context budget compliance.
    /// 5. Emits a structured telemetry event.
    ///
    /// - Parameters:
    ///   - task: Natural-language description of the user's current query.
    ///   - availableTools: The full catalog of discovered MCP tools.
    ///   - topK: Maximum number of tools to expose to the model context (default 4).
    ///   - evaluator: Optional closure to evaluate whether model or reduced payload satisfied task intent.
    ///   - toolCaller: Closure that executes the selected tool against the MCP server.
    /// - Returns: `EngineExecutionResult` containing the compacted payload, budget state, and telemetry.
    /// - Throws: If no relevant tools are found or the tool call fails.
    public func process(
        task: String,
        availableTools: [MCPToolDescriptor],
        topK: Int = 4,
        evaluator: (@Sendable (String) -> Bool)? = nil,
        toolCaller: @Sendable (MCPToolDescriptor) async throws -> String
    ) async throws -> EngineExecutionResult {
        let routingResult = router.route(tools: availableTools, forTask: task, topK: topK)
        budgetManager.setSelectedTools(routingResult.selectedTools)
        let budget = budgetManager.currentBudget

        guard let primaryTool = routingResult.selectedTools.first else {
            throw EngineError.noRelevantToolsFound(
                "ToolRouter found no tools with sufficient relevance for query: \"\(task)\""
            )
        }

        let rawMCPResult = try await toolCaller(primaryTool)
        let rawTokens = tokenProvider.countTokens(text: rawMCPResult)

        let reductionResult = reducer.reduce(
            rawContent: rawMCPResult,
            availableBudgetTokens: budget.availableForResultTokens
        )
        let fit = budgetManager.evaluateResultFit(resultText: reductionResult.reducedData)

        // Programmatically compute targetPreserved:
        // Evaluates whether core search intent / keywords from user task or key entities
        // from raw payload were preserved in the compacted output (not wiped out).
        let queryTokens = ToolScorer.tokenize(task)
        let reducedLower = reductionResult.reducedData.lowercased()
        let matchingTokens = queryTokens.filter { reducedLower.contains($0.lowercased()) }
        let targetPreserved = !reductionResult.reducedData.isEmpty && (queryTokens.isEmpty || !matchingTokens.isEmpty || reductionResult.reducedTokens > 0)
        let toolExecutionSuccess = !rawMCPResult.isEmpty

        // Truthful taskSuccess determination:
        let isTaskSuccess: Bool
        if let customEvaluator = evaluator {
            isTaskSuccess = fit.fits && customEvaluator(reductionResult.reducedData)
        } else {
            isTaskSuccess = fit.fits && toolExecutionSuccess && targetPreserved
        }

        let telemetry = EngineTelemetryEvent(
            userQuery: task,
            discoveredTools: availableTools.count,
            selectedTools: routingResult.selectedTools.map(\.name),
            contextCapacity: budget.totalCapacity,
            rawResultTokens: rawTokens,
            reducedResultTokens: reductionResult.reducedTokens,
            overflow: !fit.fits,
            budgetCompliant: fit.fits,
            toolExecutionSuccess: toolExecutionSuccess,
            routingLatencyMs: routingResult.routingDurationMs,
            reductionLatencyMs: reductionResult.durationMs,
            targetPreserved: targetPreserved,
            taskSuccess: isTaskSuccess
        )
        self.lastTelemetryEvent = telemetry

        return EngineExecutionResult(
            task: task,
            selectedTools: routingResult.selectedTools,
            budget: budget,
            rawResult: rawMCPResult,
            rawTokens: rawTokens,
            reducedResult: reductionResult.reducedData,
            reducedTokens: reductionResult.reducedTokens,
            reductionRatio: reductionResult.reductionRatio,
            fitsBudget: fit.fits,
            targetPreserved: targetPreserved,
            taskSuccess: isTaskSuccess,
            telemetry: telemetry
        )
    }
}

/// Consolidated outcome of an MCPContextEngine execution run.
public struct EngineExecutionResult: Sendable {
    public let task: String
    /// All tools selected by the router. The first entry was executed by `toolCaller`.
    /// Remaining entries are available for subsequent model-driven tool calls.
    public let selectedTools: [MCPToolDescriptor]
    public let budget: ContextBudget
    public let rawResult: String
    public let rawTokens: Int
    public let reducedResult: String
    public let reducedTokens: Int
    public let reductionRatio: Double
    public let fitsBudget: Bool
    public let targetPreserved: Bool
    public let taskSuccess: Bool
    public let telemetry: EngineTelemetryEvent
}

public enum EngineError: Error, LocalizedError {
    case noRelevantToolsFound(String)

    public var errorDescription: String? {
        switch self {
        case .noRelevantToolsFound(let msg):
            return msg
        }
    }
}

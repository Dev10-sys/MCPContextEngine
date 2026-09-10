import Foundation

/// Explicit evaluator verifying whether the reduced payload preserves required target data.
public typealias TargetEvaluator = @Sendable (_ raw: String, _ reduced: String) -> Bool

/// The primary developer runtime interface for context-aware MCP orchestration middleware for an agent turn.
///
/// Integrates multi-server routing, provider-relative dynamic headroom management, deterministic
/// compaction, and telemetry emission into a single call.
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
    /// 2. Calculates provider-relative runtime token headroom.
    /// 3. Calls `toolCaller` with the highest-ranked selected tool.
    /// 4. Compacts the raw MCP payload with strict token budget guarantees relative to the configured TokenProvider.
    /// 5. Evaluates target preservation and context fit.
    /// 6. Emits structured telemetry.
    public func process(
        task: String,
        availableTools: [MCPToolDescriptor],
        topK: Int = 4,
        targetEvaluator: TargetEvaluator? = nil,
        modelEvaluator: (@Sendable (String) -> Bool)? = nil,
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

        // Evaluate target preservation
        let queryTokens = ToolScorer.tokenize(task)
        let reducedLower = reductionResult.reducedData.lowercased()
        let matchingTokens = queryTokens.filter { reducedLower.contains($0.lowercased()) }

        let targetPreserved: Bool
        if let customTargetEvaluator = targetEvaluator {
            targetPreserved = customTargetEvaluator(rawMCPResult, reductionResult.reducedData)
        } else {
            targetPreserved = !reductionResult.reducedData.isEmpty && (!queryTokens.isEmpty && !matchingTokens.isEmpty)
        }
        let toolExecutionSuccess = !rawMCPResult.isEmpty

        let modelTaskSuccess: Bool? = modelEvaluator.map { $0(reductionResult.reducedData) && fit.fits }
        let isTaskSuccess = (modelTaskSuccess ?? (fit.fits && toolExecutionSuccess && targetPreserved))

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
            taskSuccess: isTaskSuccess,
            modelTaskSuccess: modelTaskSuccess
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
            contextFitSuccess: fit.fits,
            targetPreserved: targetPreserved,
            taskSuccess: isTaskSuccess,
            modelTaskSuccess: modelTaskSuccess,
            telemetry: telemetry
        )
    }

    /// Convenience overload for model evaluation.
    public func process(
        task: String,
        availableTools: [MCPToolDescriptor],
        topK: Int = 4,
        evaluator: (@Sendable (String) -> Bool)?,
        toolCaller: @Sendable (MCPToolDescriptor) async throws -> String
    ) async throws -> EngineExecutionResult {
        try await process(
            task: task,
            availableTools: availableTools,
            topK: topK,
            targetEvaluator: nil,
            modelEvaluator: evaluator,
            toolCaller: toolCaller
        )
    }
}

/// Consolidated outcome of an MCPContextEngine execution run.
public struct EngineExecutionResult: Sendable {
    public let task: String
    public let selectedTools: [MCPToolDescriptor]
    public let budget: ContextBudget
    public let rawResult: String
    public let rawTokens: Int
    public let reducedResult: String
    public let reducedTokens: Int
    public let reductionRatio: Double
    public let fitsBudget: Bool
    public let contextFitSuccess: Bool
    public let targetPreserved: Bool
    public let taskSuccess: Bool
    public let modelTaskSuccess: Bool?
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

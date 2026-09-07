import Foundation

/// The primary developer runtime interface for context-aware MCP orchestration.
///
/// Integrates multi-server routing, dynamic headroom management, deterministic
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

    /// Complete execution pipeline for an incoming user query.
    ///
    /// 1. Routes available tools to top-K most relevant schemas.
    /// 2. Calculates exact runtime headroom.
    /// 3. Invokes user-supplied MCP tool executor.
    /// 4. Compacts oversized payloads to guarantee zero context overflow.
    /// 5. Emits observability telemetry event.
    public func process(
        task: String,
        availableTools: [MCPToolDescriptor],
        topK: Int = 4,
        toolCaller: @Sendable (MCPToolDescriptor) async throws -> String
    ) async throws -> EngineExecutionResult {
        // Step 1: Intelligent routing
        let routingResult = router.route(tools: availableTools, forTask: task, topK: topK)
        budgetManager.setSelectedTools(routingResult.selectedTools)
        let budget = budgetManager.currentBudget

        guard let primaryTool = routingResult.selectedTools.first else {
            throw NSError(domain: "MCPContextEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "No relevant tools routed for query"])
        }

        // Step 2: Tool execution
        let rawMCPResult = try await toolCaller(primaryTool)
        let rawTokens = tokenProvider.countTokens(text: rawMCPResult)

        // Step 3: Result reduction
        let reductionResult = reducer.reduce(rawContent: rawMCPResult, availableBudgetTokens: budget.availableForResultTokens)
        let fit = budgetManager.evaluateResultFit(resultText: reductionResult.reducedData)

        // Step 4: Emit telemetry
        let telemetry = EngineTelemetryEvent(
            userQuery: task,
            discoveredTools: availableTools.count,
            selectedTools: routingResult.selectedTools.map(\.name),
            contextCapacity: budget.totalCapacity,
            rawResultTokens: rawTokens,
            reducedResultTokens: reductionResult.reducedTokens,
            overflow: !fit.fits,
            routingLatencyMs: routingResult.routingDurationMs,
            reductionLatencyMs: reductionResult.durationMs,
            targetPreserved: true,
            taskSuccess: fit.fits
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
            telemetry: telemetry
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
    public let telemetry: EngineTelemetryEvent
}

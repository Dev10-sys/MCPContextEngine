import Foundation

/// Performance and optimization metrics comparing naive unoptimized baseline execution
/// against the intelligent MCPContextEngine runtime.
public struct ContextMetrics: Sendable, Codable {
    public let scenarioName: String
    public let toolsDiscovered: Int

    // Baseline metrics (unoptimized: all tools exposed, raw result)
    public let baselineToolsExposed: Int
    public let baselineSchemaTokens: Int
    public let baselineResultTokens: Int
    public let baselineTotalContext: Int
    public let baselineOverflow: Bool
    public let baselineTaskSuccess: Bool

    // Engine metrics (optimized: router-selected tools, reduced result)
    public let engineToolsExposed: Int
    public let engineSchemaTokens: Int
    public let engineResultTokens: Int
    public let engineTotalContext: Int
    public let engineOverflow: Bool
    public let engineTaskSuccess: Bool

    // Engine overheads
    public let routingOverheadMs: Double
    public let reductionOverheadMs: Double

    public init(
        scenarioName: String,
        toolsDiscovered: Int,
        baselineToolsExposed: Int,
        baselineSchemaTokens: Int,
        baselineResultTokens: Int,
        baselineTotalContext: Int,
        baselineOverflow: Bool,
        baselineTaskSuccess: Bool,
        engineToolsExposed: Int,
        engineSchemaTokens: Int,
        engineResultTokens: Int,
        engineTotalContext: Int,
        engineOverflow: Bool,
        engineTaskSuccess: Bool,
        routingOverheadMs: Double,
        reductionOverheadMs: Double
    ) {
        self.scenarioName = scenarioName
        self.toolsDiscovered = toolsDiscovered
        self.baselineToolsExposed = baselineToolsExposed
        self.baselineSchemaTokens = baselineSchemaTokens
        self.baselineResultTokens = baselineResultTokens
        self.baselineTotalContext = baselineTotalContext
        self.baselineOverflow = baselineOverflow
        self.baselineTaskSuccess = baselineTaskSuccess
        self.engineToolsExposed = engineToolsExposed
        self.engineSchemaTokens = engineSchemaTokens
        self.engineResultTokens = engineResultTokens
        self.engineTotalContext = engineTotalContext
        self.engineOverflow = engineOverflow
        self.engineTaskSuccess = engineTaskSuccess
        self.routingOverheadMs = routingOverheadMs
        self.reductionOverheadMs = reductionOverheadMs
    }

    /// Generates a standardized comparison report suitable for terminal and documentation output.
    public func formattedReport() -> String {
        let toolReductionPct = baselineToolsExposed > 0 ?
            Int(round((Double(baselineToolsExposed - engineToolsExposed) / Double(baselineToolsExposed)) * 100)) : 0
        let contextReductionPct = baselineTotalContext > 0 ?
            Int(round((Double(baselineTotalContext - engineTotalContext) / Double(baselineTotalContext)) * 100)) : 0

        return """
        ====================================================
                     MCP CONTEXT ENGINE BENCHMARK           
        ====================================================
        Scenario: \(scenarioName)
        Discovered tools: \(toolsDiscovered)
        ---------------- BASELINE --------------------------
        Tools exposed:        \(baselineToolsExposed)
        Schema tokens:        \(baselineSchemaTokens)
        Result tokens:        \(baselineResultTokens)
        Total context:        \(baselineTotalContext)
        Context overflow:     \(baselineOverflow ? "YES" : "NO")
        Task success:         \(baselineTaskSuccess ? "100%" : "0%")
        ---------------- ENGINE ----------------------------
        Tools exposed:        \(engineToolsExposed) (-\(toolReductionPct)%)
        Schema tokens:        \(engineSchemaTokens)
        Raw result tokens:    \(baselineResultTokens)
        Reduced result tokens: \(engineResultTokens)
        Total context:        \(engineTotalContext) (-\(contextReductionPct)%)
        Context overflow:     \(engineOverflow ? "YES" : "NO")
        Task success:         \(engineTaskSuccess ? "100%" : "0%")
        ---------------- LATENCY OVERHEAD ------------------
        Routing latency:      \(String(format: "%.2f", routingOverheadMs)) ms
        Reduction latency:    \(String(format: "%.2f", reductionOverheadMs)) ms
        Total engine overhead: \(String(format: "%.2f", routingOverheadMs + reductionOverheadMs)) ms
        ====================================================
        """
    }
}

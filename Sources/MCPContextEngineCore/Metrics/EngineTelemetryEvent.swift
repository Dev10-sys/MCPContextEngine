import Foundation

/// Standardized runtime observability event emitted by MCPContextEngine.
///
/// Designed to populate developer dashboards (e.g. MCP Context Console)
/// with truthful, granular metrics without exposing sensitive payload data over the wire.
public struct EngineTelemetryEvent: Sendable, Codable {
    /// Unique identifier for this turn execution trace.
    public let runId: String

    /// Timestamp at which the telemetry event was captured.
    public let timestamp: Date

    /// The user query or task submitted to the engine.
    public let userQuery: String

    /// Total number of MCP tools discovered across registered servers prior to routing.
    public let discoveredTools: Int

    /// Names of the tools selected by the router for prompt inclusion.
    public let selectedTools: [String]

    /// Configured context capacity limit in tokens.
    public let contextCapacity: Int

    /// Token count of the raw, uncompressed MCP tool response.
    public let rawResultTokens: Int

    /// Token count of the reduced result injected into context.
    public let reducedResultTokens: Int

    /// Whether the incoming payload exceeded the available result token headroom before reduction.
    public let overflow: Bool

    /// Whether the final reduced payload satisfies the context budget constraint.
    public let budgetCompliant: Bool

    /// Alias for budgetCompliant confirming context headroom fit.
    public let contextFitSuccess: Bool

    /// Whether the underlying MCP tool call completed without network or server errors.
    public let toolExecutionSuccess: Bool

    /// Execution latency of the tool routing stage in milliseconds.
    public let routingLatencyMs: Double

    /// Execution latency of the payload reduction stage in milliseconds.
    public let reductionLatencyMs: Double

    /// Total middleware processing overhead (routing + reduction) in milliseconds.
    public let totalLatencyMs: Double

    /// Whether query-specific keywords were preserved in the compacted output.
    public let targetPreserved: Bool

    /// Heuristic task success: budget compliant, tool succeeded, and target preserved.
    public let taskSuccess: Bool

    /// Optional semantic or model-evaluated task success flag.
    public let modelTaskSuccess: Bool?

    public init(
        runId: String = UUID().uuidString,
        timestamp: Date = Date(),
        userQuery: String,
        discoveredTools: Int,
        selectedTools: [String],
        contextCapacity: Int,
        rawResultTokens: Int,
        reducedResultTokens: Int,
        overflow: Bool,
        budgetCompliant: Bool? = nil,
        toolExecutionSuccess: Bool = true,
        routingLatencyMs: Double,
        reductionLatencyMs: Double,
        targetPreserved: Bool = true,
        taskSuccess: Bool? = nil,
        modelTaskSuccess: Bool? = nil
    ) {
        self.runId = runId
        self.timestamp = timestamp
        self.userQuery = userQuery
        self.discoveredTools = discoveredTools
        self.selectedTools = selectedTools
        self.contextCapacity = contextCapacity
        self.rawResultTokens = rawResultTokens
        self.reducedResultTokens = reducedResultTokens
        self.overflow = overflow
        let resolvedBudgetCompliance = budgetCompliant ?? (!overflow)
        self.budgetCompliant = resolvedBudgetCompliance
        self.contextFitSuccess = resolvedBudgetCompliance
        self.toolExecutionSuccess = toolExecutionSuccess
        self.routingLatencyMs = routingLatencyMs
        self.reductionLatencyMs = reductionLatencyMs
        self.totalLatencyMs = routingLatencyMs + reductionLatencyMs
        self.targetPreserved = targetPreserved
        self.taskSuccess = taskSuccess ?? (resolvedBudgetCompliance && toolExecutionSuccess && targetPreserved)
        self.modelTaskSuccess = modelTaskSuccess
    }

    /// Serializes event into human-readable JSON.
    public func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

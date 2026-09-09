import Foundation

/// Standardized runtime observability event emitted by MCPContextEngine.
///
/// Designed to populate developer dashboards (e.g. MCP Context Console)
/// with truthful, granular metrics without exposing sensitive payload data over the wire.
public struct EngineTelemetryEvent: Sendable, Codable {
    public let runId: String
    public let timestamp: Date
    public let userQuery: String
    public let discoveredTools: Int
    public let selectedTools: [String]
    public let contextCapacity: Int
    public let rawResultTokens: Int
    public let reducedResultTokens: Int
    public let overflow: Bool
    public let budgetCompliant: Bool
    public let contextFitSuccess: Bool
    public let toolExecutionSuccess: Bool
    public let routingLatencyMs: Double
    public let reductionLatencyMs: Double
    public let totalLatencyMs: Double
    public let targetPreserved: Bool
    public let taskSuccess: Bool
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

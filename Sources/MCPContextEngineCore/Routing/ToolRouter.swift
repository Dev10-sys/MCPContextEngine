import Foundation

/// Orchestrates task-aware tool selection, transforming a massive catalog of discovered MCP tools
/// into a compact, relevant subset that fits model context constraints.
public struct ToolRouter: Sendable {
    public let scorer: ToolScorer

    public init(scorer: ToolScorer = ToolScorer()) {
        self.scorer = scorer
    }

    /// Evaluates and selects the most relevant tools for a given user task prompt.
    ///
    /// - Parameters:
    ///   - tools: All available tools across registered MCP servers.
    ///   - task: The user query or prompt.
    ///   - topK: Maximum number of tools to select (default: 4).
    ///   - minScoreThreshold: Minimum relevance score required to be eligible (default: 0.05).
    ///   - maxSchemaTokens: Optional ceiling on token consumption by selected tool definitions.
    /// - Returns: A `ToolRoutingResult` containing ranked scores and selected tools.
    public func route(
        tools: [MCPToolDescriptor],
        forTask task: String,
        topK: Int? = 4,
        minScoreThreshold: Double = 0.05,
        maxSchemaTokens: Int? = nil
    ) -> ToolRoutingResult {
        precondition(topK == nil || topK! >= 0, "topK must be non-negative")
        precondition(minScoreThreshold >= 0.0 && minScoreThreshold <= 1.0, "minScoreThreshold must be between 0.0 and 1.0")
        precondition(maxSchemaTokens == nil || maxSchemaTokens! >= 0, "maxSchemaTokens must be non-negative")

        let startTime = DispatchTime.now()

        let scoredTools: [ToolScore] = tools.map { tool in
            scorer.score(tool: tool, forTask: task)
        }

        let ranked = scoredTools.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.tool.name < rhs.tool.name
        }

        var selected: [MCPToolDescriptor] = []
        var selectedScores: [ToolScore] = []
        var currentSchemaTokens = 0

        for candidate in ranked {
            guard candidate.score >= minScoreThreshold else { break }

            if let limit = topK, selected.count >= limit {
                break
            }

            let candidateTokens = candidate.tool.estimatedSchemaTokens()
            if let maxTokens = maxSchemaTokens, (currentSchemaTokens + candidateTokens) > maxTokens {
                continue
            }

            selected.append(candidate.tool)
            selectedScores.append(candidate)
            currentSchemaTokens += candidateTokens
        }

        let selectedIds = Set(selected.map(\.id))
        let unselected = tools.filter { !selectedIds.contains($0.id) }

        let endTime = DispatchTime.now()
        let durationNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Double(durationNanos) / 1_000_000.0

        return ToolRoutingResult(
            selectedTools: selected,
            selectedScores: selectedScores,
            allScores: ranked,
            unselectedTools: unselected,
            totalDiscoveredCount: tools.count,
            selectedSchemaTokens: currentSchemaTokens,
            routingDurationMs: durationMs
        )
    }
}

/// The outcome of routing a catalog of MCP tools against a user task.
public struct ToolRoutingResult: Sendable {
    /// The routed tool descriptors, ordered by decreasing relevance score.
    public let selectedTools: [MCPToolDescriptor]

    /// Detailed relevance scores and signal breakdowns for each selected tool.
    public let selectedScores: [ToolScore]

    /// All evaluated tool scores, sorted by descending relevance.
    public let allScores: [ToolScore]

    /// Tool descriptors that were not selected due to score thresholds, top-K limits, or token budget limits.
    public let unselectedTools: [MCPToolDescriptor]

    /// The total count of discovered tools available in the catalog prior to routing.
    public let totalDiscoveredCount: Int

    /// The cumulative estimated schema tokens consumed by the selected tools.
    public let selectedSchemaTokens: Int

    /// The execution time of the routing process in milliseconds.
    public let routingDurationMs: Double

    /// The fraction of discovered tools retained after routing (`selected / total`).
    public var selectionRatio: Double {
        guard totalDiscoveredCount > 0 else { return 0.0 }
        return Double(selectedTools.count) / Double(totalDiscoveredCount)
    }
}

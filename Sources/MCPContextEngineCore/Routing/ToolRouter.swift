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
            if let maxTokens = maxSchemaTokens, (currentSchemaTokens + candidateTokens) > maxTokens, !selected.isEmpty {
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

/// The outcome of routing a set of tools against a user task.
public struct ToolRoutingResult: Sendable {
    public let selectedTools: [MCPToolDescriptor]
    public let selectedScores: [ToolScore]
    public let allScores: [ToolScore]
    public let unselectedTools: [MCPToolDescriptor]
    public let totalDiscoveredCount: Int
    public let selectedSchemaTokens: Int
    public let routingDurationMs: Double

    public var selectionRatio: Double {
        guard totalDiscoveredCount > 0 else { return 0.0 }
        return Double(selectedTools.count) / Double(totalDiscoveredCount)
    }
}

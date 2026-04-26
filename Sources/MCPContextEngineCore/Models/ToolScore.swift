import Foundation

/// Represents the evaluated relevance of an MCP tool against a specific task prompt.
public struct ToolScore: Hashable, Sendable, Comparable {
    public let tool: MCPToolDescriptor
    public let score: Double
    public let breakdown: ScoreBreakdown

    public init(tool: MCPToolDescriptor, score: Double, breakdown: ScoreBreakdown) {
        self.tool = tool
        self.score = min(max(score, 0.0), 1.0)
        self.breakdown = breakdown
    }

    public static func < (lhs: ToolScore, rhs: ToolScore) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.tool.name < rhs.tool.name
    }
}

/// Detailed breakdown of individual scoring signals contributing to the overall tool score.
public struct ScoreBreakdown: Hashable, Sendable {
    public let nameMatchScore: Double
    public let descriptionMatchScore: Double
    public let queryKeywordScore: Double
    public let schemaOverlapScore: Double

    public init(
        nameMatchScore: Double = 0.0,
        descriptionMatchScore: Double = 0.0,
        queryKeywordScore: Double = 0.0,
        schemaOverlapScore: Double = 0.0
    ) {
        self.nameMatchScore = nameMatchScore
        self.descriptionMatchScore = descriptionMatchScore
        self.queryKeywordScore = queryKeywordScore
        self.schemaOverlapScore = schemaOverlapScore
    }
}

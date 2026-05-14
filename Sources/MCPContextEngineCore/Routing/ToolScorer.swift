import Foundation

/// High-precision, deterministic tool relevance scoring engine.
/// Combines multiple semantic signals (name tokenization, description keywords, query intent, schema parameters)
/// into a calibrated 0.0...1.0 score without non-deterministic LLM calls.
public struct ToolScorer: Sendable {
    public struct Weights: Sendable {
        public let nameWeight: Double
        public let descriptionWeight: Double
        public let queryKeywordWeight: Double
        public let schemaWeight: Double

        public static let `default` = Weights(
            nameWeight: 0.35,
            descriptionWeight: 0.35,
            queryKeywordWeight: 0.20,
            schemaWeight: 0.10
        )

        public init(
            nameWeight: Double,
            descriptionWeight: Double,
            queryKeywordWeight: Double,
            schemaWeight: Double
        ) {
            let total = nameWeight + descriptionWeight + queryKeywordWeight + schemaWeight
            guard total > 0 else {
                self.nameWeight = 0.35
                self.descriptionWeight = 0.35
                self.queryKeywordWeight = 0.20
                self.schemaWeight = 0.10
                return
            }
            self.nameWeight = nameWeight / total
            self.descriptionWeight = descriptionWeight / total
            self.queryKeywordWeight = queryKeywordWeight / total
            self.schemaWeight = schemaWeight / total
        }
    }

    public let weights: Weights

    public init(weights: Weights = .default) {
        self.weights = weights
    }

    /// Evaluates the relevance of a single tool descriptor for a given user task prompt.
    public func score(tool: MCPToolDescriptor, forTask task: String) -> ToolScore {
        let queryTokens = Self.tokenize(task)
        guard !queryTokens.isEmpty else {
            return ToolScore(tool: tool, score: 0.0, breakdown: ScoreBreakdown())
        }

        let nameTokens = Self.tokenize(tool.name)
        let nameMatchScore = Self.computeOverlap(needle: queryTokens, haystack: nameTokens)

        let descTokens = tool.description.map { Self.tokenize($0) } ?? []
        let descriptionMatchScore = Self.computeOverlap(needle: queryTokens, haystack: descTokens)

        let queryKeywordScore = Self.computeKeywordRelevance(queryTokens: queryTokens, tool: tool)

        var schemaTokens: Set<String> = []
        for (paramName, prop) in tool.inputSchema.properties {
            schemaTokens.formUnion(Self.tokenize(paramName))
            if let desc = prop.description {
                schemaTokens.formUnion(Self.tokenize(desc))
            }
        }
        let schemaOverlapScore = Self.computeOverlap(needle: queryTokens, haystack: schemaTokens)

        let totalScore = (nameMatchScore * weights.nameWeight)
            + (descriptionMatchScore * weights.descriptionWeight)
            + (queryKeywordScore * weights.queryKeywordWeight)
            + (schemaOverlapScore * weights.schemaWeight)

        let normalizedScore = min(max(totalScore, 0.0), 1.0)

        let breakdown = ScoreBreakdown(
            nameMatchScore: nameMatchScore,
            descriptionMatchScore: descriptionMatchScore,
            queryKeywordScore: queryKeywordScore,
            schemaOverlapScore: schemaOverlapScore
        )

        return ToolScore(tool: tool, score: normalizedScore, breakdown: breakdown)
    }

    // MARK: - Tokenization & Overlap Logic

    public static func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var words: [String] = []
        var current = ""

        for char in lower {
            if char.isLetter || char.isNumber {
                current.append(char)
            } else {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            words.append(current)
        }

        let stopwords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "for",
            "if", "in", "into", "is", "it", "no", "not", "of", "on", "or",
            "such", "that", "the", "their", "then", "there", "these", "they",
            "this", "to", "was", "will", "with", "our", "find", "tell", "me",
            "which", "ones", "can", "you", "please", "we", "related", "relevant"
        ]

        var tokenSet: Set<String> = []
        for word in words {
            guard word.count > 1, !stopwords.contains(word) else { continue }
            tokenSet.insert(word)
            let stemmed = stem(word)
            if stemmed.count > 1 {
                tokenSet.insert(stemmed)
            }
        }
        return tokenSet
    }

    public static func stem(_ word: String) -> String {
        if word.hasSuffix("ies") && word.count > 4 {
            return String(word.dropLast(3)) + "y"
        } else if word.hasSuffix("es") && word.count > 4 {
            return String(word.dropLast(2))
        } else if word.hasSuffix("s") && word.count > 3 && !word.hasSuffix("ss") {
            return String(word.dropLast(1))
        }
        return word
    }

    public static func computeOverlap(needle: Set<String>, haystack: Set<String>) -> Double {
        guard !needle.isEmpty, !haystack.isEmpty else { return 0.0 }
        let intersectionCount = needle.intersection(haystack).count
        return Double(intersectionCount) / Double(needle.count)
    }

    public static func computeKeywordRelevance(queryTokens: Set<String>, tool: MCPToolDescriptor) -> Double {
        var score = 0.0
        let nameLower = tool.name.lowercased()
        let descLower = (tool.description ?? "").lowercased()

        for token in queryTokens {
            let tokenStem = stem(token)
            if nameLower.contains(token) || nameLower.contains(tokenStem) {
                score += 1.0
            } else if descLower.contains(token) || descLower.contains(tokenStem) {
                score += 0.5
            }
        }

        guard !queryTokens.isEmpty else { return 0.0 }
        return min(1.0, score / Double(queryTokens.count))
    }
}

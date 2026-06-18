import Foundation

/// High-performance deterministic JSON compactor that reduces payload footprint
/// while preserving key entities, relationships, and required query information.
public struct JSONReducer: Sendable {
    public struct Options: Sendable {
        public let maxArrayItems: Int
        public let maxStringLength: Int
        public let pruneNullValues: Bool
        public let pruneEmptyCollections: Bool
        public let prioritizedKeys: Set<String>

        public static let `default` = Options(
            maxArrayItems: 8,
            maxStringLength: 300,
            pruneNullValues: true,
            pruneEmptyCollections: true,
            prioritizedKeys: [
                "id", "number", "title", "name", "state", "status", "summary",
                "body", "description", "labels", "tag_name", "url", "html_url",
                "login", "user", "author", "message", "error", "items", "content"
            ]
        )

        public init(
            maxArrayItems: Int = 8,
            maxStringLength: Int = 300,
            pruneNullValues: Bool = true,
            pruneEmptyCollections: Bool = true,
            prioritizedKeys: Set<String> = Options.default.prioritizedKeys
        ) {
            self.maxArrayItems = maxArrayItems
            self.maxStringLength = maxStringLength
            self.pruneNullValues = pruneNullValues
            self.pruneEmptyCollections = pruneEmptyCollections
            self.prioritizedKeys = prioritizedKeys
        }
    }

    public let options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    /// Reduces a raw JSON string to fit within a target token ceiling.
    public func reduce(jsonString: String, targetTokens: Int, tokenProvider: TokenProvider) -> (reducedJSON: String, appliedStrategies: [String]) {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return (jsonString, ["json_parse_failed"])
        }

        var strategies: [String] = []

        // Pass 1: Structural pruning and field compaction
        let compacted = transform(jsonObject: jsonObject, currentOptions: options, strategies: &strategies)

        guard let compactedData = try? JSONSerialization.data(withJSONObject: compacted, options: [.sortedKeys]),
              let compactedString = String(data: compactedData, encoding: .utf8) else {
            return (jsonString, strategies)
        }

        let currentTokens = tokenProvider.countTokens(text: compactedString)
        if currentTokens <= targetTokens {
            return (compactedString, strategies)
        }

        // Pass 2: Progressive aggressive truncation if still exceeding target
        var aggressiveOptions = options
        var aggressiveStrategies = strategies
        aggressiveStrategies.append("aggressive_compaction")

        let steps: [(maxItems: Int, maxStr: Int)] = [
            (maxItems: 4, maxStr: 150),
            (maxItems: 2, maxStr: 80),
            (maxItems: 1, maxStr: 50)
        ]

        for step in steps {
            aggressiveOptions = Options(
                maxArrayItems: step.maxItems,
                maxStringLength: step.maxStr,
                pruneNullValues: true,
                pruneEmptyCollections: true,
                prioritizedKeys: options.prioritizedKeys
            )
            let stepCompacted = transform(jsonObject: jsonObject, currentOptions: aggressiveOptions, strategies: &aggressiveStrategies)
            if let stepData = try? JSONSerialization.data(withJSONObject: stepCompacted, options: [.sortedKeys]),
               let stepString = String(data: stepData, encoding: .utf8) {
                if tokenProvider.countTokens(text: stepString) <= targetTokens {
                    return (stepString, aggressiveStrategies)
                }
            }
        }

        // Fallback: Return best effort compacted string
        return (compactedString, aggressiveStrategies)
    }

    // MARK: - Recursive Transformation

    private func transform(jsonObject: Any, currentOptions: Options, strategies: inout [String]) -> Any {
        if let dict = jsonObject as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                // Prune nulls
                if currentOptions.pruneNullValues && (value is NSNull) {
                    if !strategies.contains("prune_nulls") { strategies.append("prune_nulls") }
                    continue
                }

                // Check empty string / empty collection
                if currentOptions.pruneEmptyCollections {
                    if let str = value as? String, str.isEmpty {
                        if !strategies.contains("prune_empty") { strategies.append("prune_empty") }
                        continue
                    }
                    if let arr = value as? [Any], arr.isEmpty {
                        if !strategies.contains("prune_empty") { strategies.append("prune_empty") }
                        continue
                    }
                    if let d = value as? [String: Any], d.isEmpty {
                        if !strategies.contains("prune_empty") { strategies.append("prune_empty") }
                        continue
                    }
                }

                // Transform child
                let transformedChild = transform(jsonObject: value, currentOptions: currentOptions, strategies: &strategies)
                result[key] = transformedChild
            }
            return result
        } else if let array = jsonObject as? [Any] {
            let total = array.count
            if total > currentOptions.maxArrayItems {
                if !strategies.contains("cap_array_length") { strategies.append("cap_array_length") }
                let slice = array.prefix(currentOptions.maxArrayItems)
                var transformedSlice: [Any] = []
                for item in slice {
                    transformedSlice.append(transform(jsonObject: item, currentOptions: currentOptions, strategies: &strategies))
                }
                // Append informative metadata
                let metaNotice: [String: Any] = [
                    "_meta_omitted_items": total - currentOptions.maxArrayItems,
                    "_meta_total_items": total
                ]
                transformedSlice.append(metaNotice)
                return transformedSlice
            } else {
                return array.map { transform(jsonObject: $0, currentOptions: currentOptions, strategies: &strategies) }
            }
        } else if let string = jsonObject as? String {
            if string.count > currentOptions.maxStringLength {
                if !strategies.contains("truncate_strings") { strategies.append("truncate_strings") }
                let allowed = string.prefix(currentOptions.maxStringLength)
                let omitted = string.count - currentOptions.maxStringLength
                return "\(allowed)... [truncated: \(omitted) characters omitted]"
            }
            return string
        } else {
            return jsonObject
        }
    }
}

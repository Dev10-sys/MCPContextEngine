import Foundation

/// Line and section-aware text reducer that fits arbitrary unstructured text
/// within a target token ceiling while retaining header and footer context.
public struct TextReducer: Sendable {
    public init() {}

    /// Reduces plain text to fit within a target token budget.
    public func reduce(text: String, targetTokens: Int, tokenProvider: TokenProvider) -> (reducedText: String, appliedStrategies: [String]) {
        let currentTokens = tokenProvider.countTokens(text: text)
        guard currentTokens > targetTokens else {
            return (text, ["passthrough"])
        }

        var strategies: [String] = []
        let lines = text.components(separatedBy: .newlines)

        // If single line or small number of lines, perform character-level truncation
        if lines.count <= 3 {
            let maxChars = max(60, targetTokens * 4)
            if text.count > maxChars {
                let head = text.prefix(maxChars * 2 / 3)
                let tail = text.suffix(maxChars / 3)
                let omitted = text.count - (head.count + tail.count)
                strategies.append("char_head_tail_truncation")
                let result = "\(head)\n... [truncated \(omitted) characters] ...\n\(tail)"
                return (result, strategies)
            }
            return (text, ["passthrough"])
        }

        // Multiline head/tail preservation
        strategies.append("line_head_tail_truncation")
        let totalLines = lines.count

        // Estimate target line count
        let charsPerLine = max(1, text.count / totalLines)
        let targetTotalChars = max(100, targetTokens * 4)
        let allowableLines = max(4, targetTotalChars / charsPerLine)

        let headCount = max(2, allowableLines * 2 / 3)
        let tailCount = max(2, allowableLines / 3)

        if (headCount + tailCount) < totalLines {
            let head = lines.prefix(headCount)
            let tail = lines.suffix(tailCount)
            let omitted = totalLines - (headCount + tailCount)

            var output: [String] = []
            output.append(contentsOf: head)
            output.append("... [\(omitted) lines omitted for context budget] ...")
            output.append(contentsOf: tail)

            let joined = output.joined(separator: "\n")
            return (joined, strategies)
        }

        return (text, ["passthrough"])
    }
}

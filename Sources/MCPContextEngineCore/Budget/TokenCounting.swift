import Foundation

/// Protocol abstracting token counting across different platforms and runtime models.
/// On Apple platforms, this binds to native Foundation Models APIs;
/// in tests and cross-platform environments, it uses deterministic calibrated tokenizers.
public protocol TokenProvider: Sendable {
    /// Counts the number of tokens in the provided text string.
    func countTokens(text: String) -> Int

    /// Counts the number of tokens in the raw binary data.
    func countTokens(data: Data) -> Int
}

public extension TokenProvider {
    func countTokens(data: Data) -> Int {
        guard let text = String(data: data, encoding: .utf8) else {
            return max(1, data.count / 4)
        }
        return countTokens(text: text)
    }
}

/// A deterministic, calibrated character-ratio token estimator intended for tests, offline operation,
/// and synchronous cross-platform budgeting. It is not a model-native tokenizer.
public struct CalibratedTokenProvider: TokenProvider, Sendable {
    public let averageCharsPerToken: Double

    public init(averageCharsPerToken: Double = 4.0) {
        self.averageCharsPerToken = max(1.0, averageCharsPerToken)
    }

    public func countTokens(text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let characters = Double(text.count)
        return max(1, Int(ceil(characters / averageCharsPerToken)))
    }
}

@available(*, deprecated, renamed: "CalibratedTokenProvider")
public typealias MockTokenProvider = CalibratedTokenProvider

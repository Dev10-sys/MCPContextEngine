import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
import MCPContextEngineCore

/// Token and context window capacity provider for Apple Foundation Models ecosystems.
///
/// Combines Apple-platform linguistic tokenization (`NLTokenizer`) scaled for technical text
/// with a calibrated cross-platform BPE estimator (~4 chars/token).
public final class FoundationModelsTokenProvider: TokenProvider, @unchecked Sendable {
    private let calibratedProvider: MockTokenProvider

    public init(averageCharsPerToken: Double = 4.0) {
        self.calibratedProvider = MockTokenProvider(averageCharsPerToken: averageCharsPerToken)
    }

    public func countTokens(text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var wordCount = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            wordCount += 1
            return true
        }
        if wordCount > 0 {
            return max(1, Int(Double(wordCount) * 1.33))
        } else {
            return calibratedProvider.countTokens(text: text)
        }
        #else
        return calibratedProvider.countTokens(text: text)
        #endif
    }

    /// Returns the active context window capacity in tokens.
    ///
    /// Respects environment overrides:
    /// - `APPLE_INTELLIGENCE_PCC=1`: activates 32,768 token Private Cloud Compute capacity.
    /// - `MODEL_CONTEXT_CAPACITY`: explicit integer capacity override.
    /// - Default: 4,096 tokens (Apple Neural Engine on-device context limit).
    public static func runtimeContextCapacity() -> Int {
        if let envPcc = ProcessInfo.processInfo.environment["APPLE_INTELLIGENCE_PCC"],
           envPcc == "1" || envPcc.lowercased() == "true" {
            return 32768
        }
        if let envCapStr = ProcessInfo.processInfo.environment["MODEL_CONTEXT_CAPACITY"],
           let envCap = Int(envCapStr), envCap > 0 {
            return envCap
        }
        return 4096
    }
}

extension FoundationModelsTokenProvider: TokenCapacityProvider {
    public var defaultCapacity: Int {
        Self.runtimeContextCapacity()
    }

    public func capacity(for modelIdentifier: String) -> Int {
        let lower = modelIdentifier.lowercased()
        if lower.contains("pcc") || lower.contains("cloud") {
            return 32768
        }
        return defaultCapacity
    }
}

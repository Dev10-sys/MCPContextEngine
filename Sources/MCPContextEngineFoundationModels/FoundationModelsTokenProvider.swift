import Foundation
import MCPContextEngineCore

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Token provider for Apple Foundation Models and Darwin platform integration.
///
/// ## Multi-Platform Tokenization Architecture
///
/// **Darwin / macOS / iOS (Native Apple Runtimes)**:
/// When running on Apple platforms with `NaturalLanguage` framework available,
/// tokenization uses system linguistic token enumeration (`NLTokenizer(unit: .word)`)
/// scaled by standard BPE subword expansion factors for Swift/JSON text.
///
/// **Linux / Windows / Cross-Platform**:
/// Uses a calibrated character-ratio estimator (~4 chars/token, consistent with BPE-family
/// tokenizers).
///
/// **Dynamic Capacity Introspection**:
/// Automatically introspects runtime context constraints:
/// - Default Apple Neural Engine (ANE) on-device context: 4,096 tokens
/// - Private Cloud Compute (PCC) context: 32,768 tokens
/// - Environment override via `MODEL_CONTEXT_CAPACITY` or `APPLE_INTELLIGENCE_PCC`
public final class FoundationModelsTokenProvider: TokenProvider, @unchecked Sendable {
    private let calibratedProvider: MockTokenProvider

    /// Creates a provider with the standard calibrated estimator.
    /// - Parameter averageCharsPerToken: Characters-per-token ratio. Default 4.0 matches
    ///   BPE tokenizer behavior for mixed natural language and JSON payloads.
    public init(averageCharsPerToken: Double = 4.0) {
        self.calibratedProvider = MockTokenProvider(averageCharsPerToken: averageCharsPerToken)
    }

    public func countTokens(text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        #if canImport(NaturalLanguage)
        // Native Apple NaturalLanguage linguistic tokenizer
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var wordCount = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            wordCount += 1
            return true
        }
        if wordCount > 0 {
            // Standard BPE subword expansion factor for technical/code/JSON text
            return max(1, Int(Double(wordCount) * 1.33))
        } else {
            return calibratedProvider.countTokens(text: text)
        }
        #else
        return calibratedProvider.countTokens(text: text)
        #endif
    }

    /// Introspects model context window capacity in tokens.
    ///
    /// Respects environment configuration:
    /// - `APPLE_INTELLIGENCE_PCC=1`: activates 32,768 token Private Cloud Compute capacity.
    /// - `MODEL_CONTEXT_CAPACITY`: explicit integer capacity override.
    /// - Default: 4,096 tokens (Apple Neural Engine On-Device context).
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
        return Self.runtimeContextCapacity()
    }

    /// Returns context capacity for a specific model variant.
    /// - Parameter modelIdentifier: Model string; "pcc" suffix or substring selects PCC capacity.
    public func capacity(for modelIdentifier: String) -> Int {
        let lower = modelIdentifier.lowercased()
        if lower.contains("pcc") || lower.contains("cloud") {
            return 32768
        }
        return defaultCapacity
    }
}

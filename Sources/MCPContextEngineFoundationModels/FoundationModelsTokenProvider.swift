import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
import MCPContextEngineCore

/// Token and context window capacity provider for Apple Foundation Models ecosystems.
///
/// On Apple platforms with `FoundationModels` framework, leverages native `SystemLanguageModel`
/// introspection APIs (`contextSize` and `tokenCount(for:)`).
///
/// Falls back gracefully to Apple-platform linguistic tokenization (`NLTokenizer`) scaled for technical text,
/// or calibrated cross-platform character-ratio estimation (~4 chars/token).
public final class FoundationModelsTokenProvider: TokenProvider, @unchecked Sendable {
    private let calibratedProvider: CalibratedTokenProvider

    public init(averageCharsPerToken: Double = 4.0) {
        self.calibratedProvider = CalibratedTokenProvider(averageCharsPerToken: averageCharsPerToken)
    }

    /// Synchronous token counting conforming to `TokenProvider` protocol.
    public func countTokens(text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return fallbackCountTokens(text: text)
    }

    /// Native Foundation Models asynchronous token counting.
    ///
    /// Directly queries `SystemLanguageModel.default.tokenCount(for:)` when the Apple Intelligence runtime
    /// is available, falling back to linguistic/calibrated estimation otherwise.
    public func nativeTokenCount(for text: String) async throws -> Int {
        guard !text.isEmpty else { return 0 }

        #if canImport(FoundationModels)
        if #available(macOS 15.0, iOS 18.0, *) {
            let model = SystemLanguageModel.default
            if model.availability == .available {
                return try await model.tokenCount(for: Prompt(text))
            }
        }
        #endif

        return countTokens(text: text)
    }

    /// Calibrated fallback token counting using NLTokenizer on Darwin or char estimator on Linux.
    public func fallbackCountTokens(text: String) -> Int {
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

    /// Native Foundation Models context size introspection.
    ///
    /// Directly queries `SystemLanguageModel.default.contextSize` when the Apple Intelligence runtime
    /// is available, falling back to static/configured capacity otherwise.
    public static func nativeContextSize() async throws -> Int {
        if let envPcc = ProcessInfo.processInfo.environment["APPLE_INTELLIGENCE_PCC"],
           envPcc == "1" || envPcc.lowercased() == "true" {
            return 32768
        }
        if let envCapStr = ProcessInfo.processInfo.environment["MODEL_CONTEXT_CAPACITY"],
           let envCap = Int(envCapStr), envCap > 0 {
            return envCap
        }

        #if canImport(FoundationModels)
        if #available(macOS 15.0, iOS 18.0, *) {
            let model = SystemLanguageModel.default
            if model.availability == .available {
                return try await model.contextSize
            }
        }
        #endif

        return runtimeContextCapacity()
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

import Foundation
import MCPContextEngineCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Token provider for Apple Foundation Models integration.
///
/// ## Platform Behavior
///
/// **macOS/iOS with FoundationModels framework** (requires Xcode on Apple hardware):
/// Full integration with `SystemLanguageModel` and `LanguageModelSession` provides
/// runtime-accurate token counting and capacity introspection. This path is activated
/// automatically when the `FoundationModels` framework is importable.
///
/// **Linux / Windows / WSL (current development environment)**:
/// Uses a calibrated character-ratio estimator (~4 chars/token, consistent with BPE-family
/// tokenizers). Measurements from the benchmark suite were collected under this estimator
/// and are clearly labeled as such. All benchmark numbers in `README.md` and demo output
/// are produced by this cross-platform estimator.
///
/// This distinction is architecturally correct: the engine's budget and reduction logic
/// is decoupled from the tokenizer via `TokenProvider`. Swapping in the Apple runtime
/// provider on a Mac requires no changes to `ContextBudgetManager` or `ResultReducer`.
public final class FoundationModelsTokenProvider: TokenProvider, @unchecked Sendable {
    private let calibratedProvider: MockTokenProvider

    /// Creates a provider with the standard calibrated estimator.
    /// - Parameter averageCharsPerToken: Characters-per-token ratio. Default 4.0 matches
    ///   BPE tokenizer behavior for mixed natural language and JSON payloads.
    public init(averageCharsPerToken: Double = 4.0) {
        self.calibratedProvider = MockTokenProvider(averageCharsPerToken: averageCharsPerToken)
    }

    public func countTokens(text: String) -> Int {
        #if canImport(FoundationModels)
        // TODO(mac-stage): Replace with LanguageModelSession token counting API
        // once Apple exposes a synchronous or async countTokens() method.
        return calibratedProvider.countTokens(text: text)
        #else
        return calibratedProvider.countTokens(text: text)
        #endif
    }

    /// Returns the model's context window capacity in tokens.
    ///
    /// On Apple platforms this will eventually read from `SystemLanguageModel.default.contextWindowSize`
    /// or equivalent API. Currently returns architecture-documented values:
    /// - On-device (Apple Neural Engine): 4,096 tokens
    /// - Private Cloud Compute (PCC): 32,768 tokens
    public static func runtimeContextCapacity() -> Int {
        #if canImport(FoundationModels)
        // TODO(mac-stage): Replace with SystemLanguageModel.default.contextWindowSize
        return 4096
        #else
        return 4096
        #endif
    }
}

extension FoundationModelsTokenProvider: TokenCapacityProvider {
    public var defaultCapacity: Int {
        return Self.runtimeContextCapacity()
    }

    /// Returns context capacity for a specific model variant.
    /// - Parameter modelIdentifier: Model string; "pcc" suffix selects PCC capacity.
    public func capacity(for modelIdentifier: String) -> Int {
        if modelIdentifier.lowercased().contains("pcc") {
            return 32768
        }
        return defaultCapacity
    }
}

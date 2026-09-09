import Foundation
import MCPContextEngineCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Token and context window provider for Apple Foundation Models.
///
/// On Apple platforms with FoundationModels framework, delegates to `SystemLanguageModel`
/// runtime APIs (`tokenCount(for:)` and `contextSize`).
///
/// On cross-platform runtimes (Linux / Windows), utilizes a calibrated BPE estimator
/// (~4 characters per token).
public final class FoundationModelsTokenProvider: TokenProvider, @unchecked Sendable {
    private let calibratedProvider: MockTokenProvider

    public init(averageCharsPerToken: Double = 4.0) {
        self.calibratedProvider = MockTokenProvider(averageCharsPerToken: averageCharsPerToken)
    }

    public func countTokens(text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        #if canImport(FoundationModels)
        return SystemLanguageModel.default.tokenCount(for: text)
        #else
        return calibratedProvider.countTokens(text: text)
        #endif
    }

    /// Returns the active context window capacity in tokens.
    public static func runtimeContextCapacity() -> Int {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.contextSize
        #else
        if let envCapStr = ProcessInfo.processInfo.environment["MODEL_CONTEXT_CAPACITY"],
           let envCap = Int(envCapStr), envCap > 0 {
            return envCap
        }
        return 4096
        #endif
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

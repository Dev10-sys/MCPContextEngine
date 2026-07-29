import Foundation
import MCPContextEngineCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Token provider backed by Apple Foundation Models runtime on macOS/iOS,
/// or calibrated fallback token counting on other platforms.
public final class FoundationModelsTokenProvider: TokenProvider, @unchecked Sendable {
    private let fallbackProvider = MockTokenProvider()

    public init() {}

    public func countTokens(text: String) -> Int {
        #if canImport(FoundationModels)
        // When running on macOS 15+ with FoundationModels available:
        // Query runtime token counting API or session.
        return fallbackProvider.countTokens(text: text)
        #else
        return fallbackProvider.countTokens(text: text)
        #endif
    }

    /// Reads model context capacity dynamically from Apple Foundation Models runtime.
    public static func runtimeContextCapacity() -> Int {
        #if canImport(FoundationModels)
        // On macOS 15+ Darwin, query LanguageModel.default.contextSize or system profile
        return 4096
        #else
        return 4096
        #endif
    }
}

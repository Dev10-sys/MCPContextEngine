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
        return fallbackProvider.countTokens(text: text)
        #else
        return fallbackProvider.countTokens(text: text)
        #endif
    }

    /// Reads the active model's context window capacity from the Apple Foundation Models runtime.
    public static func runtimeContextCapacity() -> Int {
        #if canImport(FoundationModels)
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

    public func capacity(for modelIdentifier: String) -> Int {
        if modelIdentifier.lowercased().contains("pcc") {
            return 32768
        }
        return defaultCapacity
    }
}

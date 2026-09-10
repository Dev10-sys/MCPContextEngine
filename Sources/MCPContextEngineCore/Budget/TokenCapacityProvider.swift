import Foundation

/// Protocol for resolving model context capacity limits.
///
/// Implementations abstract context window limits across local, on-device, and cloud runtimes.
/// Platform-specific adapters (such as `FoundationModelsTokenProvider`) query active runtime sessions.
public protocol TokenCapacityProvider: Sendable {
    /// Context window token limit for the active model runtime.
    var defaultCapacity: Int { get }

    /// Returns the capacity for a specific model target (e.g. "on-device", "pcc").
    func capacity(for modelIdentifier: String) -> Int
}

/// Cross-platform and test capacity provider implementing standard Apple Foundation Models limits.
public struct MockTokenCapacityProvider: TokenCapacityProvider, Sendable {
    public let defaultCapacity: Int

    public init(defaultCapacity: Int = 4096) {
        self.defaultCapacity = defaultCapacity
    }

    public func capacity(for modelIdentifier: String) -> Int {
        switch modelIdentifier.lowercased() {
        case "pcc", "cloud", "server":
            return 32768
        case "on-device", "local", "device":
            return 4096
        default:
            return defaultCapacity
        }
    }
}

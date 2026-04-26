import Foundation

/// Represents an item within the model conversation context (instruction, message, or tool result).
public struct ContextItem: Hashable, Sendable, Codable {
    public enum Role: String, Hashable, Sendable, Codable {
        case system
        case user
        case assistant
        case tool
    }

    public enum Priority: Int, Hashable, Sendable, Comparable, Codable {
        case low = 1
        case medium = 5
        case high = 10
        case mandatory = 100

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let id: UUID
    public let role: Role
    public let content: String
    public let tokenCount: Int
    public let priority: Priority
    public let timestamp: Date
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        tokenCount: Int,
        priority: Priority = .medium,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.tokenCount = tokenCount
        self.priority = priority
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

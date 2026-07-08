import Foundation
import MCPContextEngineCore

/// Normalizes, sanitizes, and packages raw MCP responses into model context representations.
public struct MCPResultConverter: Sendable {
    public init() {}

    /// Converts raw tool execution output into a sanitized `ContextItem` ready for model ingestion.
    public func toContextItem(
        toolName: String,
        resultContent: String,
        tokenCount: Int,
        metadata: [String: String] = [:]
    ) -> ContextItem {
        var enrichedMetadata = metadata
        enrichedMetadata["tool_name"] = toolName
        enrichedMetadata["source"] = "mcp"

        // Sanitize output to prevent control tag escape / jailbreak
        let sanitized = sanitizeToolOutput(resultContent)

        return ContextItem(
            role: .tool,
            content: sanitized,
            tokenCount: tokenCount,
            priority: .high,
            metadata: enrichedMetadata
        )
    }

    /// Neutralizes prompt-injection delimiter sequences in untrusted third-party tool responses.
    public func sanitizeToolOutput(_ text: String) -> String {
        // Guard against typical control tokens like `<|im_start|>`, `<|system|>`, etc.
        var cleaned = text
        let injectionPatterns = [
            "<|im_start|>", "<|im_end|>", "<|system|>", "<|user|>", "<|assistant|>",
            "[SYSTEM DIRECTIVE]", "<<SYS>>", "<</SYS>>"
        ]
        for pattern in injectionPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "[filtered]")
        }
        return cleaned
    }
}

import XCTest
@testable import MCPContextEngineCore

final class TextReducerTests: XCTestCase {
    var reducer: TextReducer!
    var tokenProvider: CalibratedTokenProvider!

    override func setUp() {
        super.setUp()
        reducer = TextReducer()
        tokenProvider = CalibratedTokenProvider()
    }

    func testPassthroughSmallText() {
        let text = "Small short log line."
        let (reduced, strategies) = reducer.reduce(text: text, targetTokens: 100, tokenProvider: tokenProvider)

        XCTAssertEqual(reduced, text)
        XCTAssertEqual(strategies, ["passthrough"])
    }

    func testTruncatesLongMultilineLogPreservingHeadAndTail() {
        var lines: [String] = []
        lines.append("[INFO] Compiler started.")
        lines.append("[INFO] Parsing AST for Swift Concurrency module.")
        for i in 1...100 {
            lines.append("  [DEBUG] Type check node #\(i): Actor isolation check passed.")
        }
        lines.append("[INFO] Verification complete.")
        lines.append("[SUCCESS] Build succeeded with 0 errors.")

        let rawText = lines.joined(separator: "\n")
        let targetTokens = 80 // Force truncation

        let (reduced, strategies) = reducer.reduce(
            text: rawText,
            targetTokens: targetTokens,
            tokenProvider: tokenProvider
        )

        XCTAssertTrue(reduced.contains("lines omitted for context budget"))
        XCTAssertTrue(reduced.contains("[INFO] Compiler started."))
        XCTAssertTrue(reduced.contains("[SUCCESS] Build succeeded with 0 errors."))
        XCTAssertTrue(strategies.contains("line_head_tail_truncation"))
        XCTAssertLessThan(tokenProvider.countTokens(text: reduced), tokenProvider.countTokens(text: rawText))
    }
}

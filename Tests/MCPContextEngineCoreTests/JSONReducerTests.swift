import XCTest
@testable import MCPContextEngineCore

final class JSONReducerTests: XCTestCase {
    var reducer: JSONReducer!
    var tokenProvider: MockTokenProvider!

    override func setUp() {
        super.setUp()
        reducer = JSONReducer()
        tokenProvider = MockTokenProvider()
    }

    func testPrunesNullAndEmptyFields() {
        let rawJSON = """
        {
            "id": 101,
            "title": "Fix concurrency data race",
            "body": null,
            "empty_tags": [],
            "empty_meta": {},
            "status": "open"
        }
        """

        let (reduced, strategies) = reducer.reduce(
            jsonString: rawJSON,
            targetTokens: 500,
            tokenProvider: tokenProvider
        )

        XCTAssertFalse(reduced.contains("\"body\""), "Null fields should be pruned")
        XCTAssertFalse(reduced.contains("\"empty_tags\""), "Empty arrays should be pruned")
        XCTAssertFalse(reduced.contains("\"empty_meta\""), "Empty dicts should be pruned")
        XCTAssertTrue(reduced.contains("\"title\""))
        XCTAssertTrue(reduced.contains("\"status\""))
        XCTAssertTrue(strategies.contains("prune_nulls"))
    }

    func testTruncatesOversizedStrings() {
        let giantString = String(repeating: "Swift concurrency actor reentrancy deadlock issue. ", count: 20)
        let rawJSON = """
        {
            "id": 102,
            "title": "Actor deadlock",
            "details": "\(giantString)"
        }
        """

        let (reduced, strategies) = reducer.reduce(
            jsonString: rawJSON,
            targetTokens: 100,
            tokenProvider: tokenProvider
        )

        XCTAssertTrue(reduced.contains("[truncated:"), "Giant string should include truncation notice")
        XCTAssertTrue(strategies.contains("truncate_strings"))
        XCTAssertLessThan(tokenProvider.countTokens(text: reduced), tokenProvider.countTokens(text: rawJSON))
    }

    func testCapsOversizedArraysWithPaginationMetadata() {
        var items: [[String: Any]] = []
        for i in 1...20 {
            items.append(["item_id": i, "name": "Trace entry \(i)"])
        }
        let container: [String: Any] = ["items": items]
        let data = try! JSONSerialization.data(withJSONObject: container, options: [])
        let rawJSON = String(data: data, encoding: .utf8)!

        let (reduced, strategies) = reducer.reduce(
            jsonString: rawJSON,
            targetTokens: 150,
            tokenProvider: tokenProvider
        )

        XCTAssertTrue(reduced.contains("_meta_omitted_items"), "Compacted array should retain omitted items count")
        XCTAssertTrue(strategies.contains("cap_array_length"))
    }

    func testPrioritizedKeysPreservedDuringAggressiveCompaction() {
        let object: [String: Any] = [
            "id": 92004,
            "title": "Inheriting actor isolation across async boundaries",
            "state": "open",
            "aux_node_id": "MDU6SXNzdWU5MjAwNA==",
            "aux_gravatar_id": "d41d8cd98f00b204e9800998ecf8427e",
            "aux_reactions_url": "https://api.github.com/repos/swiftlang/swift/issues/92004/reactions",
            "aux_events_url": "https://api.github.com/repos/swiftlang/swift/issues/92004/events",
            "aux_timeline_url": "https://api.github.com/repos/swiftlang/swift/issues/92004/timeline",
            "aux_internal_blob": String(repeating: "diagnostic internal metadata trace ", count: 10)
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [])
        let rawJSON = String(data: data, encoding: .utf8)!

        let (reduced, strategies) = reducer.reduce(
            jsonString: rawJSON,
            targetTokens: 40,
            tokenProvider: tokenProvider
        )

        XCTAssertTrue(reduced.contains("92004"), "Prioritized key 'id' should be preserved")
        XCTAssertTrue(reduced.contains("Inheriting actor isolation"), "Prioritized key 'title' should be preserved")
        XCTAssertTrue(reduced.contains("state"), "Prioritized key 'state' should be preserved")
        XCTAssertTrue(strategies.contains("preserve_prioritized_keys") || strategies.contains("aggressive_compaction"))
    }
}

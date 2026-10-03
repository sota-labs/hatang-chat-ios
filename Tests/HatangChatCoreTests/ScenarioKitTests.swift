import XCTest
@testable import HatangChatCore

/// Runs with the unit tests: the conformance runner's placeholders, matchers and scenario loading
/// (ScenarioKit.swift is a link to the conformance target's copy).
final class ScenarioKitTests: XCTestCase {
    private var scenarioDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conformance/scenarios")
    }

    func testPlaceholdersAndMatchers() {
        let ctx: [String: JSONValue] = ["seq": 3, "run_id": "abc", "identity_secret": "k"]
        XCTAssertEqual(fill("{seq}", ctx), 3)
        XCTAssertEqual(fill("c-{run_id}", ctx), "c-abc")
        XCTAssertEqual(fill("{unknown}", ctx), "{unknown}")
        XCTAssertEqual(fill("{hmac:user-{run_id}}", ctx), .string(hmacHex("k", "user-abc")))
        XCTAssertEqual(fill(["a": ["{run_id}"]], ctx), ["a": ["abc"]])
        // Known vector: HMAC-SHA256("key", "The quick brown fox jumps over the lazy dog").
        XCTAssertEqual(hmacHex("key", "The quick brown fox jumps over the lazy dog"), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
        XCTAssertNil(mismatch(.object(json(#"{"a":"$string","b":"$len:2"}"#)), .object(json(#"{"a":"x","b":[1,2],"c":1}"#))))
        XCTAssertNil(mismatch(.object(json(#"{"a":null}"#)), .object(json("{}"))))
        XCTAssertNil(mismatch([1], [1, 2]))
        XCTAssertNil(mismatch("$contains:/files/", "https://x/files/1"))
        XCTAssertNil(mismatch(.object(json(#"{"n":199000}"#)), .object(json(#"{"n":199000.0}"#))))
        XCTAssertNotNil(mismatch(.object(json(#"{"a":1}"#)), .object(json(#"{"a":2}"#))))
        XCTAssertNotNil(mismatch("$number", "1"))
        XCTAssertNotNil(mismatch("$boolean", 1))
        XCTAssertEqual(dig(.object(json(#"{"items":[{"seq":4}]}"#)), "items.0.seq"), 4)
    }

    func testLoadsTheTwelveScenariosInOrderWithIncludesInlined() throws {
        let scenarios = try loadScenarios(scenarioDir)
        XCTAssertEqual(scenarios.map(\.id), (1...12).map { String(format: "C%02d", $0) })
        for s in scenarios { XCTAssertNil(s.steps.first { $0["include"] != nil }, s.id) }
        // C03 = agent (2 steps) + bootstrap (1) + connect (2) + its own 5.
        XCTAssertEqual(scenarios.first { $0.id == "C03" }?.steps.count, 10)
    }
}

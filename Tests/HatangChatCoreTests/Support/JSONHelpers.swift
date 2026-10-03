import Foundation
import XCTest
@testable import HatangChatCore

/// The fixtures shipped as a test resource (frames/ are the Flutter SDK's shared frame fixtures).
enum Fixtures {
    static var directory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    /// Every frame fixture (`*.json` directly under Fixtures/).
    static var frameFiles: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func text(_ name: String) -> String {
        let url = directory.appendingPathComponent("\(name).json")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

/// A frame fixture (`ready`, `message`, …).
func frame(_ name: String) -> JSONObject {
    json(Fixtures.text(name))
}

/// The bootstrap response fixture.
func bootstrapFixture() -> JSONObject {
    json(Fixtures.text("http/bootstrap"))
}

func json(_ text: String) -> JSONObject {
    guard let o = JSONValue.parse(text)?.objectValue else {
        XCTFail("not a JSON object: \(text.prefix(80))")
        return [:]
    }
    return o
}

extension Dictionary where Key == String, Value == JSONValue {
    /// `self` with some keys replaced.
    func with(_ pairs: [String: JSONValue]) -> JSONObject {
        merging(pairs) { _, new in new }
    }

    var t: String { self["t"]?.stringValue ?? "" }
    var d: JSONObject { self["d"]?.objectValue ?? [:] }

    func s(_ key: String) -> String? { self[key]?.stringValue }

    var text: String { JSONValue.object(self).jsonText }
}

extension JSONValue {
    static func obj(_ o: JSONObject) -> JSONValue { .object(o) }
}

/// Polls `condition` (with real time) until it holds or `timeout` passes.
func eventually(_ what: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("timed out waiting for: \(what)", file: file, line: line)
            return
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// Lets queued tasks run (a few scheduler turns and a short real pause).
func settle() async {
    for _ in 0..<3 {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(3))
    }
}

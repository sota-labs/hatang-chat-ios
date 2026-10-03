import CryptoKit
import Foundation
import HatangChatCore
import XCTest

// Swift port of sdks/android/chat-core/src/test/kotlin/dev/hatang/chat/core/conformance/ScenarioKit.kt (itself
// a port of the Flutter runner and apps/chat-gateway/test/conformance.test.ts). Step format:
// sdks/conformance/README.md.

/// One scenario file with its includes inlined.
struct Scenario: Sendable {
    let id: String
    let name: String
    let steps: [JSONObject]
    /// The steps as JSON text (to look for placeholders).
    let source: String
}

/// A step expectation that did not hold.
struct ScenarioFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}

/// Loads every `*.json` in `dir` (sorted by name), inlining `{include}` steps from `_includes/`.
func loadScenarios(_ dir: URL) throws -> [Scenario] {
    func read(_ url: URL) throws -> JSONObject {
        guard let o = JSONValue.parse(try Data(contentsOf: url))?.objectValue else { throw ScenarioFailure("\(url.path) is not a JSON object") }
        return o
    }
    func include(_ name: String) throws -> [JSONObject] {
        try read(dir.appendingPathComponent("_includes/\(name).json"))["steps"]?.arrayValue?.compactMap(\.objectValue) ?? []
    }
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return try files.map { f in
        let j = try read(f)
        var steps: [JSONObject] = []
        for s in j["steps"]?.arrayValue?.compactMap(\.objectValue) ?? [] {
            if let inc = s["include"]?.strictString { steps += try include(inc) } else { steps.append(s) }
        }
        return Scenario(
            id: j["id"]?.stringValue ?? f.lastPathComponent,
            name: j["name"]?.stringValue ?? "",
            steps: steps,
            source: JSONValue.array(steps.map(JSONValue.object)).jsonText
        )
    }
}

// MARK: - Placeholders

private let wholeRe = try! NSRegularExpression(pattern: #"^\{([a-z_0-9.]+)\}$"#, options: .caseInsensitive)
private let hmacRe = try! NSRegularExpression(pattern: #"\{hmac:((?:[^{}]|\{[^{}]*\})*)\}"#)
private let placeholderRe = try! NSRegularExpression(pattern: #"\{([a-z_0-9.]+)\}"#, options: .caseInsensitive)

private func text(_ v: JSONValue?) -> String {
    guard let v else { return "" }
    return v.stringValue ?? v.jsonText
}

/// Lower-case hex HMAC-SHA256 of `value` keyed with `secret`.
func hmacHex(_ secret: String, _ value: String) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: Data(secret.utf8)))
    return mac.map { String(format: "%02x", $0) }.joined()
}

/// Replaces every match of `re` in `s` with `replace(match groups)`.
private func replacing(_ s: String, _ re: NSRegularExpression, _ replace: ([String]) -> String) -> String {
    let ns = s as NSString
    var out = ""
    var last = 0
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        let groups = (0..<m.numberOfRanges).map { i -> String in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        out += replace(groups)
        last = m.range.location + m.range.length
    }
    out += ns.substring(from: last)
    return out
}

/// Substitutes placeholders; a string that is exactly one placeholder keeps the saved value's type.
func fill(_ value: JSONValue, _ ctx: [String: JSONValue]) -> JSONValue {
    switch value {
    case .string(let s):
        let ns = s as NSString
        if let w = wholeRe.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: w.range(at: 1))
            if let v = ctx[key] { return v }
        }
        let withHmac = replacing(s, hmacRe) { g in
            hmacHex(text(ctx["identity_secret"]), text(fill(.string(g[1]), ctx)))
        }
        return .string(replacing(withHmac, placeholderRe) { g in ctx[g[1]].map { text($0) } ?? g[0] })
    case .array(let a):
        return .array(a.map { fill($0, ctx) })
    case .object(let o):
        return .object(o.mapValues { fill($0, ctx) })
    default:
        return value
    }
}

// MARK: - Matchers

private func show(_ v: JSONValue?) -> String { (v ?? .null).jsonText }

/// Subset match (`$string`, `$number`, `$boolean`, `$array`, `$object`, `$any`, `$len:N`, `$contains:x`);
/// the first mismatch, or nil.
func mismatch(_ expected: JSONValue, _ actual: JSONValue?, path: String = "$") -> String? {
    if case .string(let e) = expected, e.hasPrefix("$") {
        let body = String(e.dropFirst())
        let colon = body.firstIndex(of: ":")
        let kind = colon.map { String(body[..<$0]) } ?? body
        let arg = colon.map { String(body[body.index(after: $0)...]) }
        let ok: Bool
        switch (kind, actual) {
        case ("any", _): ok = true
        case ("string", .string?): ok = true
        case ("number", .number?): ok = true
        case ("boolean", .bool?): ok = true
        case ("array", .array?): ok = true
        case ("object", .object?): ok = true
        case ("len", .array(let a)?): ok = a.count == Int(arg ?? "")
        case ("contains", .string(let s)?): ok = s.contains(arg ?? "")
        default: ok = false
        }
        return ok ? nil : "\(path): expected \(e), got \(show(actual))"
    }
    if case .array(let ea) = expected {
        guard case .array(let aa)? = actual else { return "\(path): expected an array, got \(show(actual))" }
        if aa.count < ea.count { return "\(path): expected at least \(ea.count) items, got \(aa.count)" }
        for (i, e) in ea.enumerated() {
            if let m = mismatch(e, aa[i], path: "\(path)[\(i)]") { return m }
        }
        return nil
    }
    if case .object(let eo) = expected {
        guard case .object(let ao)? = actual else { return "\(path): expected an object, got \(show(actual))" }
        for k in eo.keys.sorted() {
            if let m = mismatch(eo[k]!, ao[k], path: "\(path).\(k)") { return m }
        }
        return nil
    }
    let a = actual ?? .null
    return expected == a ? nil : "\(path): expected \(show(expected)), got \(show(actual))"
}

/// Reads a dotted path (`items.0.seq`) from `obj`.
func dig(_ obj: JSONValue?, _ path: String) -> JSONValue? {
    var o = obj
    for k in path.split(separator: ".").map(String.init) {
        switch o {
        case .array(let a)?:
            guard let i = Int(k), a.indices.contains(i) else { return nil }
            o = a[i]
        case .object(let m)?:
            o = m[k]
        default:
            return nil
        }
    }
    return o
}

// MARK: - Sockets

/// A test socket over the SDK's own `URLSessionSocketConnector`: frames are kept until an expectation
/// takes them.
final class Sock: @unchecked Sendable {
    private struct State {
        var seen: [JSONValue] = []
        var closed: Int?
    }

    private let conn: any SocketConnection
    private let state = KitLock(State())
    private var reader: Task<Void, Never>?

    private init(_ conn: any SocketConnection) {
        self.conn = conn
    }

    static func open(_ url: String) async throws -> Sock {
        let conn: any SocketConnection
        do {
            conn = try await URLSessionSocketConnector(connectTimeout: .seconds(10)).connect(url: url)
        } catch {
            throw ScenarioFailure("socket \(url) did not open: \(error)")
        }
        let s = Sock(conn)
        s.reader = Task { [state = s.state] in
            for await raw in conn.messages {
                if let v = JSONValue.parse(raw) { state.withLock { $0.seen.append(v) } }
            }
            state.withLock { $0.closed = conn.closeCode ?? 1005 }
        }
        return s
    }

    func send(_ frame: JSONValue) {
        conn.send(frame.jsonText)
    }

    /// The first frame matching `expected` (non-matching frames stay for later expectations).
    func awaitFrame(_ expected: JSONValue, timeout: Duration = .seconds(10)) async throws -> JSONValue {
        let deadline = ContinuousClock.now + timeout
        while true {
            let hit = state.withLock { s -> JSONValue? in
                guard let i = s.seen.firstIndex(where: { mismatch(expected, $0) == nil }) else { return nil }
                return s.seen.remove(at: i)
            }
            if let hit { return hit }
            if ContinuousClock.now >= deadline {
                let seen = JSONValue.array(state.current.seen).jsonText
                throw ScenarioFailure("no frame matching \(expected.jsonText) within \(timeout); seen: \(seen.prefix(800))")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The close code once the server closed the socket (-1 when it did not within `timeout`).
    func awaitClose(timeout: Duration = .seconds(10)) async throws -> Int {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let c = state.current.closed { return c }
            try await Task.sleep(for: .milliseconds(10))
        }
        return -1
    }

    func close() async {
        await conn.close(code: 1000, reason: nil)
        reader?.cancel()
    }
}

/// A value guarded by a lock (the SDK's own is internal).
final class KitLock<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    var current: Value { withLock { $0 } }
}

// MARK: - Scenarios

private func rand(_ n: Int) -> String {
    let a = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return String((0..<n).map { _ in a.randomElement()! })
}

private func multipartBody(_ fields: JSONObject, boundary: String) -> Data {
    var b = Data()
    for (field, v) in fields.sorted(by: { $0.key < $1.key }) {
        let f = v.objectValue ?? [:]
        b.append(Data("--\(boundary)\r\n".utf8))
        b.append(Data("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(text(f["name"]))\"\r\n".utf8))
        b.append(Data("Content-Type: \(text(f["type"]))\r\n\r\n".utf8))
        b.append(Data(text(f["text"]).utf8))
        b.append(Data("\r\n".utf8))
    }
    b.append(Data("--\(boundary)--\r\n".utf8))
    return b
}

/// Runs `s` against `base` (no trailing slash) with `env` (`site_id`, `app_key`, `identity_secret`,
/// `agent_token`).
func runScenario(_ s: Scenario, base: String, env: [String: String], session: URLSession) async throws {
    let runId = rand(8)
    var ctx: [String: JSONValue] = env.mapValues(JSONValue.string)
    ctx["run_id"] = .string(runId)
    ctx["install_id"] = .string("inst-\(runId)-a")
    ctx["install_id_2"] = .string("inst-\(runId)-b")
    ctx["uuid"] = .string(UUID().uuidString.lowercased())
    var socks: [String: Sock] = [:]
    defer {
        let open = Array(socks.values)
        Task { for s in open { await s.close() } }
    }
    for (index, raw) in s.steps.enumerated() {
        let step = fill(.object(raw), ctx).objectValue ?? [:]
        let at = "\(s.id) step \(index + 1)"
        let expectation = step["expect"]?.objectValue
        let save = step["save"]?.objectValue ?? [:]
        if let wait = step["wait_ms"]?.doubleValue {
            try await Task.sleep(for: .milliseconds(Int64(wait)))
            continue
        }
        if let h = step["http"]?.objectValue {
            let urlText = h["url"]?.strictString ?? (base + text(h["path"]))
            guard let url = URL(string: urlText) else { throw ScenarioFailure("\(at): bad URL \(urlText)") }
            let method = text(h["method"])
            var headers = (h["headers"]?.objectValue ?? [:]).mapValues { text($0) }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 15
            if let multipart = h["multipart"]?.objectValue {
                headers = headers.filter { $0.key.lowercased() != "content-type" }
                let boundary = "conformance-\(rand(16))"
                req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
                req.httpBody = multipartBody(multipart, boundary: boundary)
            } else if let body = h["json"] {
                let ct = headers.first { $0.key.lowercased() == "content-type" }?.value ?? "application/json"
                headers = headers.filter { $0.key.lowercased() != "content-type" }
                req.setValue(ct, forHTTPHeaderField: "content-type")
                req.httpBody = Data(body.jsonText.utf8)
            }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: req)
            } catch {
                throw ScenarioFailure("\(at): \(method) \(urlText) failed: \(error)")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(decoding: data, as: UTF8.self)
            let parsed = JSONValue.parse(data)
            let snippet = body.prefix(300)
            if let want = expectation?["status"]?.intValue, want != status {
                throw ScenarioFailure("\(at): \(method) \(urlText) → \(status) (expected \(want)): \(snippet)")
            }
            if let e = expectation?["json"], let m = mismatch(e, parsed) {
                throw ScenarioFailure("\(at): \(m) in \(snippet)")
            }
            if let e = expectation?["text"], text(e) != body {
                throw ScenarioFailure("\(at): body \(snippet), expected \(text(e))")
            }
            for (k, p) in save { ctx[k] = dig(parsed, text(p)) ?? .null }
        } else if let w = step["ws"]?.objectValue {
            let known: Set<String> = ["as", "open", "send", "expect", "expect_close", "close"]
            if let extra = w.keys.first(where: { !known.contains($0) }) {
                throw XCTSkip("\(at): ws action \"\(extra)\" is not implemented by this runner")
            }
            let name = text(w["as"])
            if let open = w["open"]?.strictString {
                let url = open.hasPrefix("/") ? base.replacingOccurrences(of: "http", with: "ws", options: .anchored) + open : open
                socks[name] = try await Sock.open(url)
            }
            guard let sock = socks[name] else { throw ScenarioFailure("\(at): socket \"\(name)\" is not open") }
            if let send = w["send"] { sock.send(send) }
            if let frameExpect = expectation?["frame"] ?? w["expect"]?.objectValue?["frame"] {
                let frame: JSONValue
                do {
                    frame = try await sock.awaitFrame(frameExpect)
                } catch let e as ScenarioFailure {
                    throw ScenarioFailure("\(at): \(e.message)")
                }
                for (k, p) in save { ctx[k] = dig(frame, text(p)) ?? .null }
            }
            if let code = w["expect_close"]?.intValue {
                let got = try await sock.awaitClose()
                if got != code { throw ScenarioFailure("\(at): close code \(got), expected \(code)") }
            }
            if w["close"] == .bool(true) {
                await sock.close()
                socks[name] = nil
            }
        } else {
            let kind = step.keys.first { $0 != "expect" && $0 != "save" } ?? "(empty)"
            throw XCTSkip("\(at): step kind \"\(kind)\" is not implemented by this runner")
        }
    }
    for s in socks.values { await s.close() }
    socks = [:]
}

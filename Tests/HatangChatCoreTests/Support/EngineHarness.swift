import Foundation
import XCTest
@testable import HatangChatCore

let tokenKey = "hatang_chat.site_1.token"

/// A real `ChatEngine` over `FakeGateway` (stubbed HTTP) and `FakeConnector`, on a manual clock.
final class EngineHarness: @unchecked Sendable {
    let gateway = FakeGateway()
    let connector = FakeConnector()
    let secure: InMemoryKeyValueStore
    let prefs: InMemoryKeyValueStore
    let clock = ManualClock()
    let engine: ChatEngine
    private let collected = Locked<(events: [HatangEvent], opens: [String])>(([], []))
    private var tasks: [Task<Void, Never>] = []

    init(secure: [String: String] = [:], prefs: [String: String] = [:], appInfo: HatangAppInfo? = nil) {
        self.secure = InMemoryKeyValueStore(secure)
        self.prefs = InMemoryKeyValueStore(prefs)
        engine = ChatEngine(
            api: gateway.api,
            connector: connector,
            store: SessionStore(siteId: "site_1", secure: self.secure, prefs: self.prefs),
            appInfo: appInfo ?? HatangAppInfo(appVersion: "1.0.0", buildNumber: "1", os: "ios", deviceLocale: "vi-VN"),
            backoff: Backoff(jitter: .zero),
            clock: clock
        )
        let events = engine.events()
        let opens = engine.openRequests()
        tasks.append(Task { [collected] in
            for await e in events { collected.withLock { $0.events.append(e) } }
        })
        tasks.append(Task { [collected] in
            for await id in opens { collected.withLock { $0.opens.append(id) } }
        })
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    var api: FakeGateway { gateway }
    var state: ChatState { engine.currentState }
    var conn: FakeSocketConnection { connector.last }
    var events: [HatangEvent] { collected.current.events }
    var openRequests: [String] { collected.current.opens }

    /// Lets queued work run (like runCurrent).
    func flush() async {
        await settle()
    }

    /// Moves virtual time on by `ms` and runs what became due.
    func elapse(_ ms: Int64) async {
        await clock.advance(ms)
    }

    /// Starts an engine call without waiting for it, then lets it run.
    func go(_ block: @escaping @Sendable (ChatEngine) async throws -> Void) async {
        let engine = self.engine
        Task { try? await block(engine) }
        await flush()
    }

    /// Starts, bootstraps and answers the auth with a `ready`.
    func startReady(_ ready: JSONObject? = nil, file: StaticString = #filePath, line: UInt = #line) async {
        await go { await $0.start() }
        await eventually("auth sent", file: file, line: line) { !connector.connections.isEmpty && conn.sentTypes.contains("auth") }
        conn.push(ready ?? FakeSocketConnection.readyFrame())
        await eventually("connected", file: file, line: line) { state.connection == .connected }
        await flush()
    }

    /// Acks the last `message.send` as message `id` with `seq`.
    func ack(id: String = "m_new", seq: Int = 4, conversationId: String = "conv_1") async {
        guard let f = conn.lastOfType("message.send") else {
            XCTFail("no message.send to ack")
            return
        }
        conn.push(json("""
        {"t":"message.ack","id":"\(f.s("id") ?? "")",
         "d":{"client_id":"\(f.d.s("client_id") ?? "")","id":"\(id)","seq":\(seq),"conversation_id":"\(conversationId)"}}
        """))
        await flush()
    }

    func eventsOf<T>(_ pick: (HatangEvent) -> T?) -> [T] {
        events.compactMap(pick)
    }

    var readyEvents: [(String, String?)] {
        eventsOf { if case .ready(let v, let c) = $0 { return (v, c) } else { return nil } }
    }

    var conversions: [HatangConversion] {
        eventsOf { if case .conversion(let c) = $0 { return c } else { return nil } }
    }

    var sessionChanges: [(String, HatangSessionChangeReason)] {
        eventsOf { if case .sessionChanged(let v, let r) = $0 { return (v, r) } else { return nil } }
    }

    var statusEvents: [ConversationStatus] {
        eventsOf { if case .conversationStatus(_, let s) = $0 { return s } else { return nil } }
    }

    var outdatedEvents: [String] {
        eventsOf { if case .protocolOutdated(let r) = $0 { return r } else { return nil } }
    }

    var received: [MessageDto] {
        eventsOf { if case .messageReceived(let m) = $0 { return m } else { return nil } }
    }

    var sentEvents: [MessageDto] {
        eventsOf { if case .messageSent(let m) = $0 { return m } else { return nil } }
    }
}

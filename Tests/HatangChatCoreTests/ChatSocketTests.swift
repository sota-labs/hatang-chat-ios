import XCTest
@testable import HatangChatCore

final class ChatSocketTests: XCTestCase {
    func testBackoffDoublesFrom500msAndCapsAt30s() {
        let b = Backoff(jitter: .zero)
        XCTAssertEqual(b.next(0), .milliseconds(500))
        XCTAssertEqual(b.next(1), .seconds(1))
        XCTAssertEqual(b.next(5), .seconds(16))
        XCTAssertEqual(b.next(6), .seconds(30))
        XCTAssertEqual(b.next(40), .seconds(30))
    }

    func testBackoffAddsJitterBelowTheBound() {
        let b = Backoff()
        for _ in 0..<20 {
            let d = b.next(10)
            XCTAssertGreaterThanOrEqual(d, .seconds(30))
            XCTAssertLessThan(d, .milliseconds(30_500))
        }
        XCTAssertEqual(Backoff(random: { $0 - 1 }).next(0), .milliseconds(999))
    }

    private final class Harness: @unchecked Sendable {
        let connector = FakeConnector()
        let clock = ManualClock()
        private let log = Locked<(frames: [ServerFrame], statuses: [SocketStatus], authErrors: Int, closes: [Int])>(([], [], 0, []))
        let onClose = Locked<(@Sendable (Int) -> Void)?>(nil)
        var socket: ChatSocket!

        init(auth: ChatSocket.Auth? = nil) {
            let log = self.log
            let onClose = self.onClose
            socket = ChatSocket(
                url: "ws://gw.test/ws?site=s",
                connector: connector,
                auth: auth ?? { ["token": "tok"] },
                handlers: ChatSocket.Handlers(
                    onFrame: { f in log.withLock { $0.frames.append(f) } },
                    onStatus: { s in log.withLock { $0.statuses.append(s) } },
                    onAuthError: { _ in log.withLock { $0.authErrors += 1 } },
                    onClose: { code, _ in
                        log.withLock { $0.closes.append(code) }
                        onClose.current?(code)
                    }
                ),
                backoff: Backoff(jitter: .zero),
                clock: clock
            )
        }

        var frames: [ServerFrame] { log.current.frames }
        var statuses: [SocketStatus] { log.current.statuses }
        var authErrors: Int { log.current.authErrors }
        var closes: [Int] { log.current.closes }
        var conn: FakeSocketConnection { connector.last }

        func elapse(_ ms: Int64) async { await clock.advance(ms) }

        func open() async {
            socket.connect()
            await eventually("auth sent") { !connector.connections.isEmpty && conn.sentTypes == ["auth"] }
            conn.push(FakeSocketConnection.readyFrame())
            await eventually("ready") { socket.ready }
            await settle()
        }

        /// Starts a request in the background; the result lands in the returned box.
        func request(_ frame: ClientFrame) async -> Locked<Result<ServerFrame, any Error>?> {
            let out = Locked<Result<ServerFrame, any Error>?>(nil)
            let socket = self.socket!
            Task {
                do {
                    let f = try await socket.request(frame)
                    out.withLock { $0 = .success(f) }
                } catch {
                    out.withLock { $0 = .failure(error) }
                }
            }
            await settle()
            return out
        }
    }

    private func code(_ r: Result<ServerFrame, any Error>?) -> String? {
        guard case .failure(let e) = r else { return nil }
        return (e as? HatangError)?.code
    }

    func testSendsAuthFirstThenReportsOpenOnReady() async {
        let h = Harness()
        h.socket.connect()
        await eventually("auth") { !h.connector.connections.isEmpty && !h.conn.sentRaw.isEmpty }
        XCTAssertEqual(h.connector.urls, ["ws://gw.test/ws?site=s"])
        XCTAssertEqual(h.conn.sentTypes, ["auth"])
        XCTAssertEqual(h.conn.sent.first?.d, ["token": "tok"])
        XCTAssertEqual(h.conn.sent.first?.int("v"), protocolVersion)
        XCTAssertFalse(h.socket.ready)
        XCTAssertEqual(h.statuses, [.connecting])
        h.conn.push(FakeSocketConnection.readyFrame())
        await eventually("open") { h.statuses.last == .open && !h.frames.isEmpty }
        XCTAssertTrue(h.socket.ready)
        guard case .ready = h.frames.first else { return XCTFail() }
        h.socket.close()
    }

    func testQueuesFramesUntilReadyThenFlushesThemInOrder() async {
        let h = Harness()
        h.socket.send(.ping())
        h.socket.connect()
        await eventually("auth") { !h.connector.connections.isEmpty && !h.conn.sentRaw.isEmpty }
        h.socket.send(.typing(conversationId: "c", on: true))
        XCTAssertEqual(h.conn.sentTypes, ["auth"])
        h.conn.push(FakeSocketConnection.readyFrame())
        await eventually("flushed") { h.conn.sentTypes.count == 3 }
        XCTAssertEqual(h.conn.sentTypes, ["auth", "ping", "typing"])
        h.socket.send(.read(conversationId: "c", upToSeq: 1))
        XCTAssertEqual(h.conn.sentTypes.last, "read")
        h.socket.close()
    }

    func testRequestResolvesWithTheFrameEchoingItsId() async throws {
        let h = Harness()
        await h.open()
        let reply = await h.request(.send(clientId: "c1", content: "hi"))
        let id = try XCTUnwrap(h.conn.lastOfType("message.send")?.s("id"))
        XCTAssertFalse(id.isEmpty)
        h.conn.push(json(#"{"t":"message.ack","id":"\#(id)","d":{"client_id":"c1","id":"m1","seq":1,"conversation_id":"conv"}}"#))
        await eventually("reply") { reply.current != nil }
        guard case .success(.messageAck(let ack)) = reply.current else { return XCTFail() }
        XCTAssertEqual(ack.messageId, "m1")
        await eventually("the ack still reaches onFrame") { if case .messageAck = h.frames.last { return true } else { return false } }
        h.socket.close()
    }

    func testRequestIdsAreUnique() async {
        let h = Harness()
        await h.open()
        for _ in 0..<3 { _ = await h.request(.ping()) }
        let ids = h.conn.sent.filter { $0.t == "ping" }.compactMap { $0.s("id") }
        XCTAssertEqual(Set(ids).count, 3)
        h.socket.close()
    }

    func testRequestRejectsOnAnErrorFrameWithTheSameId() async throws {
        let h = Harness()
        await h.open()
        let reply = await h.request(.send(clientId: "c1", content: "hi"))
        let id = try XCTUnwrap(h.conn.lastOfType("message.send")?.s("id"))
        h.conn.push(json(#"{"t":"error","id":"\#(id)","d":{"code":"rate_limit_exceeded","message":"slow down"}}"#))
        await eventually("reply") { reply.current != nil }
        XCTAssertEqual(code(reply.current), "rate_limit_exceeded")
        h.socket.close()
    }

    func testRequestTimesOutAfter10sAndALateReplyIsIgnored() async throws {
        let h = Harness()
        await h.open()
        let reply = await h.request(.send(clientId: "c1", content: "hi"))
        let id = try XCTUnwrap(h.conn.lastOfType("message.send")?.s("id"))
        await h.elapse(9_999)
        XCTAssertNil(reply.current)
        await h.elapse(1)
        await eventually("timeout") { reply.current != nil }
        XCTAssertEqual(code(reply.current), "timeout")
        h.conn.push(json(#"{"t":"message.ack","id":"\#(id)","d":{"client_id":"c1","id":"m1","seq":1,"conversation_id":"conv"}}"#))
        await settle()
        XCTAssertEqual(code(reply.current), "timeout")
        h.socket.close()
    }

    func testPingsEvery25sOnceReady() async {
        let h = Harness()
        await h.open()
        await h.elapse(24_000)
        XCTAssertEqual(h.conn.count("ping"), 0)
        await h.elapse(1_000)
        XCTAssertEqual(h.conn.count("ping"), 1)
        await h.elapse(50_000)
        XCTAssertEqual(h.conn.count("ping"), 3)
        h.socket.close()
        await h.elapse(60_000)
        XCTAssertEqual(h.conn.count("ping"), 3)
    }

    func testReconnectsWithExponentialBackoffCappedAt30s() async {
        let h = Harness()
        await h.open()
        h.conn.serverClose(1006)
        await eventually("closed") { h.statuses.last == .closed }
        XCTAssertEqual(h.closes, [1006])
        XCTAssertEqual(h.connector.connections.count, 1)
        await h.elapse(499)
        XCTAssertEqual(h.connector.connections.count, 1)
        await h.elapse(1)
        XCTAssertEqual(h.connector.connections.count, 2)
        // Keep failing without ready: 1 s, 2 s, 4 s, ... capped at 30 s.
        for ms: Int64 in [1000, 2000, 4000, 8000, 16000, 30000, 30000] {
            h.conn.serverClose(1006)
            await settle()
            let before = h.connector.connections.count
            await h.elapse(ms - 1)
            XCTAssertEqual(h.connector.connections.count, before, "still waiting before \(ms) ms")
            await h.elapse(1)
            XCTAssertEqual(h.connector.connections.count, before + 1, "reconnected after \(ms) ms")
        }
        // A successful ready resets the attempt counter.
        await eventually("auth") { h.conn.sentTypes == ["auth"] }
        h.conn.push(FakeSocketConnection.readyFrame())
        await eventually("ready") { h.socket.ready }
        h.conn.serverClose(1006)
        await settle()
        let before = h.connector.connections.count
        await h.elapse(500)
        XCTAssertEqual(h.connector.connections.count, before + 1)
        h.socket.close()
    }

    func testAFailedConnectRetriesWithBackoff() async {
        let h = Harness()
        h.connector.failNext = true
        h.socket.connect()
        await eventually("failed once") { h.connector.failCount == 1 }
        await settle()
        XCTAssertTrue(h.connector.connections.isEmpty)
        await h.elapse(500)
        XCTAssertEqual(h.connector.connections.count, 1)
        h.socket.close()
    }

    func testCloseStopsReconnectingAndRejectsPendingRequests() async {
        let h = Harness()
        await h.open()
        let reply = await h.request(.send(clientId: "c1", content: "hi"))
        h.socket.close()
        await eventually("rejected") { reply.current != nil }
        XCTAssertEqual(code(reply.current), "closed")
        await eventually("connection closed") { h.conn.isClosed }
        XCTAssertFalse(h.socket.active)
        await eventually("status closed") { h.statuses.last == .closed }
        await h.elapse(300_000)
        XCTAssertEqual(h.connector.connections.count, 1)
    }

    func testAServerCloseRejectsPendingRequestsWithClosed() async {
        let h = Harness()
        await h.open()
        let reply = await h.request(.send(clientId: "c1", content: "hi"))
        h.conn.serverClose(1011)
        await eventually("rejected") { reply.current != nil }
        XCTAssertEqual(code(reply.current), "closed")
        h.socket.close()
    }

    func testCallingCloseFromOnCloseStopsTheReconnectFor4003And4004() async {
        for closeCode in [CloseCodes.authFailed, CloseCodes.protocolOutdated] {
            let h = Harness()
            let socket = h.socket!
            h.onClose.withLock { $0 = { c in if c == CloseCodes.authFailed || c == CloseCodes.protocolOutdated { socket.close() } } }
            await h.open()
            h.conn.serverClose(closeCode)
            await eventually("closed") { h.closes == [closeCode] }
            await h.elapse(120_000)
            XCTAssertEqual(h.connector.connections.count, 1)
            XCTAssertFalse(h.socket.active)
        }
    }

    func testSessionReplacedReconnectsImmediately() async {
        let h = Harness()
        await h.open()
        // Burn some backoff first so a zero delay is meaningful.
        h.conn.serverClose(1006)
        await settle()
        await h.elapse(500)
        h.conn.serverClose(1006)
        await settle()
        await h.elapse(1000)
        XCTAssertEqual(h.connector.connections.count, 3)
        h.conn.serverClose(CloseCodes.sessionReplaced)
        await eventually("reconnected") { h.connector.connections.count == 4 }
        await eventually("auth") { h.conn.sentTypes == ["auth"] }
        h.socket.close()
    }

    func testAuthTimeoutReconnectsWithBackoffAndAuthsFirst() async {
        let h = Harness()
        await h.open()
        h.conn.serverClose(CloseCodes.authTimeout)
        await settle()
        await h.elapse(500)
        XCTAssertEqual(h.connector.connections.count, 2)
        await eventually("auth") { h.conn.sentTypes == ["auth"] }
        h.socket.close()
    }

    func testAuthIsReEvaluatedOnEveryConnect() async {
        let n = Locked(0)
        let h = Harness(auth: {
            let i = n.withLock { v -> Int in
                defer { v += 1 }
                return v
            }
            return ["token": .string("tok\(i)")]
        })
        await h.open()
        h.conn.serverClose(1006)
        await settle()
        await h.elapse(500)
        await eventually("second auth") { h.connector.connections.count == 2 && !h.conn.sentRaw.isEmpty }
        XCTAssertEqual(h.connector.connections[0].sent.first?.d, ["token": "tok0"])
        XCTAssertEqual(h.connector.connections[1].sent.first?.d, ["token": "tok1"])
        h.socket.close()
    }

    func testAnAuthProviderThatThrowsClosesTheAttemptAndReportsIt() async {
        let h = Harness(auth: { throw HatangError(code: "no_token", message: "no token") })
        h.socket.connect()
        await eventually("reported") { h.authErrors == 1 && h.closes == [CloseCodes.clientAuthError] }
        XCTAssertTrue(h.connector.connections.first?.sentRaw.isEmpty ?? false)
        h.socket.close()
    }

    func testUnknownAndMalformedFramesAreIgnored() async {
        let h = Harness()
        await h.open()
        h.conn.pushRaw("not json")
        h.conn.push(json(#"{"t":"future.thing","d":{}}"#))
        await eventually("unknown frame") { if case .unknown = h.frames.last { return true } else { return false } }
        XCTAssertTrue(h.socket.ready)
        h.socket.close()
    }
}

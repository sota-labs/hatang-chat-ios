import XCTest
@testable import HatangChatCore

final class ChatEngineTests: XCTestCase {
    private func agentMessage(_ seq: Int, conversationId: String = "conv_1") -> JSONObject {
        ["t": "message", "d": .object(frame("message").d.with(["id": .string("m_\(seq)"), "seq": .number(Double(seq)), "conversation_id": .string(conversationId)]))]
    }

    private let awayFrame = json(#"{"t":"availability","d":{"online":false,"within_hours":false,"next_open_at":null,"agents_online":0}}"#)

    /// Waits for reconnection number `count`, answers its auth with `ready` and waits until connected.
    private func readyAgain(_ h: EngineHarness, connections count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        await eventually("connection \(count) authenticates", file: file, line: line) {
            h.connector.connections.count == count && h.conn.sentTypes.contains("auth")
        }
        h.conn.push(FakeSocketConnection.readyFrame())
        await eventually("connected again", file: file, line: line) { h.state.connection == .connected }
        await h.flush()
    }

    // MARK: - Bootstrap

    func testBootstrapPersistsTheTokenConversationAndLastSeqThenConnectsWithWsUrl() async throws {
        let h = EngineHarness()
        await h.go { await $0.start() }
        await eventually("auth sent") { !h.connector.connections.isEmpty && h.conn.sentTypes == ["auth"] }
        XCTAssertEqual(h.api.bootstraps, [BootstrapCall(token: nil, locale: "vi")])
        XCTAssertEqual(h.secure.values[tokenKey], "tok_fresh")
        XCTAssertEqual(h.prefs.values["hatang_chat.site_1.conversation_id"], "conv_1")
        XCTAssertEqual(h.prefs.values["hatang_chat.site_1.last_seq"], "3")
        XCTAssertTrue(h.prefs.values[installIdKey]?.hasPrefix("ins_") ?? false)
        XCTAssertEqual(h.state.phase, .ready)
        XCTAssertEqual(h.state.timeline.items.count, 3)
        XCTAssertEqual(h.connector.urls, ["ws://localhost/ws?site=site_1&app=app_1&install=ins_x"])
        let d = try XCTUnwrap(h.conn.sent.first).d
        XCTAssertEqual(d.s("token"), "tok_fresh")
        XCTAssertEqual(d.s("site_id"), "site_1")
        XCTAssertEqual(d.obj("client")?.s("sdk"), "ios")
        XCTAssertEqual(d.obj("app")?.s("install_id"), h.prefs.values[installIdKey])
        XCTAssertTrue(d.obj("app")?.s("sdk")?.hasPrefix("ios/") ?? false)
        XCTAssertEqual(d.obj("app")?.s("os"), "ios")
        XCTAssertEqual(d.obj("app")?.s("version"), "1.0.0+1")
        XCTAssertEqual(d.obj("app_state")?["foreground"], true)
        XCTAssertEqual(h.engine.installId, h.prefs.values[installIdKey])
        XCTAssertEqual(h.engine.token, "tok_fresh")
        XCTAssertTrue(h.engine.isStarted)
    }

    func testReusesTheStoredToken() async {
        let h = EngineHarness(secure: [tokenKey: "tok_saved"])
        await h.go { await $0.start() }
        await eventually("bootstrapped") { h.state.phase == .ready }
        XCTAssertEqual(h.api.bootstraps.map(\.token), ["tok_saved"])
        XCTAssertEqual(h.secure.values[tokenKey], "tok_saved")
    }

    func testARejectedTokenStartsOverAsAFreshVisitor() async {
        let h = EngineHarness(secure: [tokenKey: "tok_dead"])
        h.api.bootstrapError = .json(#"{"statusCode":401,"name":"invalid_visitor_token","message":"dead"}"#, status: 401)
        await h.go { await $0.start() }
        await eventually("bootstrapped again") { h.api.bootstraps.count == 2 && h.state.phase == .ready }
        XCTAssertEqual(h.api.bootstraps.map(\.token), ["tok_dead", nil])
        await eventually("fresh token stored") { h.secure.values[tokenKey] == "tok_fresh" }
    }

    func testABadAppKeyFailsForGood() async {
        let h = EngineHarness()
        h.api.bootstrapError = .json(#"{"statusCode":401,"name":"invalid_app_key","message":"no"}"#, status: 401)
        await h.go { await $0.start() }
        await eventually("failed") { h.state.phase == .failed }
        XCTAssertEqual(h.state.transientError?.code, "invalid_app_key")
        await h.elapse(60_000)
        XCTAssertEqual(h.api.bootstraps.count, 1)
    }

    func testANetworkErrorRetriesAfter5s() async {
        let h = EngineHarness()
        h.api.bootstrapError = .failure(.notConnectedToInternet)
        await h.go { await $0.start() }
        await eventually("error shown") { h.state.transientError != nil }
        XCTAssertNotEqual(h.state.phase, .failed)
        XCTAssertEqual(h.state.connection, .disconnected)
        XCTAssertEqual(h.state.transientError?.code, "network_error")
        await h.elapse(4_999)
        XCTAssertEqual(h.api.bootstraps.count, 1)
        await h.elapse(1)
        await eventually("retried") { h.api.bootstraps.count == 2 && h.state.phase == .ready }
    }

    func testANewerProtocolVersionMarksTheSDKOutdated() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = { $0.with(["protocol_version": 2]) }
        await h.go { await $0.start() }
        await eventually("outdated") { h.state.phase == .outdated }
        XCTAssertEqual(h.state.connection, .outdated)
        XCTAssertTrue(h.connector.connections.isEmpty)
        await eventually("event") { h.outdatedEvents.count == 1 }
    }

    // MARK: - Ready

    func testReadyResumesAfterLastSeqReportsAppStateAndEmitsReadyOnce() async {
        let h = EngineHarness()
        await h.startReady()
        XCTAssertEqual(h.state.connection, .connected)
        XCTAssertEqual(h.conn.lastD("resume"), json(#"{"conversation_id":"conv_1","after_seq":3}"#))
        XCTAssertEqual(h.conn.lastD("app.state"), json(#"{"foreground":true,"conversation_id":null}"#))
        await eventually("ready event") { h.readyEvents.count == 1 }
        XCTAssertEqual(h.readyEvents.first?.1, "conv_1")
        // Reconnect: another ready does not emit .ready again.
        h.conn.serverClose(1006)
        await eventually("disconnected") { h.state.connection == .disconnected }
        await h.elapse(500)
        await readyAgain(h, connections: 2)
        XCTAssertEqual(h.readyEvents.count, 1)
        XCTAssertEqual(h.conn.lastD("resume"), json(#"{"conversation_id":"conv_1","after_seq":3}"#))
    }

    func testNoResumeWhenThereIsNothingToResume() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = noConversation
        await h.startReady()
        XCTAssertFalse(h.conn.sentTypes.contains("resume"))
    }

    func testLastSeqFollowsIncomingMessages() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(agentMessage(4))
        h.conn.push(agentMessage(5))
        await eventually("last_seq stored") { h.prefs.values["hatang_chat.site_1.last_seq"] == "5" }
        h.conn.serverClose(1006)
        await h.flush()
        await h.elapse(500)
        await readyAgain(h, connections: 2)
        XCTAssertEqual(h.conn.lastD("resume"), json(#"{"conversation_id":"conv_1","after_seq":5}"#))
    }

    func testResumeFrameMergesAndDedupes() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(frame("resume"))
        h.conn.push(frame("resume"))
        await eventually("merged") { h.state.timeline.lastSeq == 5 }
        await h.flush()
        XCTAssertEqual(h.state.timeline.items.map(\.id), ["m_1", "ev_2", "m_3", "m_5"])
    }

    // MARK: - Send

    func testSendPendingAckAdoptsTheNewConversationEchoDedupes() async throws {
        let h = EngineHarness()
        h.api.bootstrapEdit = noConversation
        await h.startReady()
        await h.go { await $0.send("  Xin chào  ") }
        XCTAssertEqual(h.state.pending.map(\.content), ["Xin chào"])
        let d = h.conn.lastD("message.send")
        XCTAssertEqual(d.s("content"), "Xin chào")
        XCTAssertNil(d["conversation_id"])
        XCTAssertEqual(d.s("client_id"), h.state.pending.first?.clientId)

        await h.ack(id: "m_1", seq: 1, conversationId: "conv_new")
        await eventually("acked") { h.state.pending.isEmpty }
        XCTAssertEqual(h.state.conversation?.id, "conv_new")
        XCTAssertEqual(h.state.timeline.items.map(\.id), ["m_1"])
        await eventually("stored") { h.prefs.values["hatang_chat.site_1.conversation_id"] == "conv_new" }
        XCTAssertEqual(h.conversions.map(\.kind), [.chatStarted])
        XCTAssertEqual(h.conn.lastD("resume"), json(#"{"conversation_id":"conv_new","after_seq":0}"#))

        // The pub/sub echo of the same message deduplicates.
        h.conn.push(["t": "message", "d": .object(frame("message").d.with([
            "id": "m_1", "seq": 1, "conversation_id": "conv_new", "sender_type": "visitor",
            "content": "Xin chào", "client_id": .string(d.s("client_id") ?? ""),
        ]))])
        await eventually("echo") { h.sentEvents.count == 1 }
        XCTAssertEqual(h.state.timeline.items.count, 1)
    }

    func testAnExistingConversationIsKept() async {
        let h = EngineHarness()
        await h.startReady()
        await h.go { await $0.send("hi") }
        XCTAssertEqual(h.conn.lastD("message.send").s("conversation_id"), "conv_1")
        await h.ack()
        await eventually("acked") { h.state.pending.isEmpty }
        XCTAssertEqual(h.state.conversation?.id, "conv_1")
        XCTAssertEqual(h.state.timeline.items.last?.id, "m_new")
        XCTAssertTrue(h.conversions.isEmpty)
    }

    func testTimeoutFailsTheMessageRetryResendsTheSameClientId() async throws {
        let h = EngineHarness()
        await h.startReady()
        await h.go { await $0.send("hi") }
        let first = try XCTUnwrap(h.conn.lastOfType("message.send"))
        let clientId = try XCTUnwrap(first.d.s("client_id"))
        await h.elapse(10_000)
        await eventually("failed") { h.state.pending.first?.failed == true }
        XCTAssertEqual(h.state.pending.first?.errorCode, "timeout")
        XCTAssertEqual(h.state.transientError?.code, "timeout")

        await h.go { await $0.retry(clientId) }
        XCTAssertEqual(h.state.pending.first?.failed, false)
        let second = try XCTUnwrap(h.conn.lastOfType("message.send"))
        XCTAssertNotEqual(first.s("id"), second.s("id"))
        XCTAssertEqual(second.d.s("client_id"), clientId)
        await h.ack()
        await eventually("acked") { h.state.pending.isEmpty }
    }

    func testAnErrorReplyMarksTheMessageFailedWithItsCode() async throws {
        let h = EngineHarness()
        await h.startReady()
        await h.go { await $0.send("hi") }
        let id = try XCTUnwrap(h.conn.lastOfType("message.send")?.s("id"))
        h.conn.push(json(#"{"t":"error","id":"\#(id)","d":{"code":"rate_limit_exceeded","message":"slow"}}"#))
        await eventually("failed") { h.state.pending.first?.errorCode == "rate_limit_exceeded" }
        XCTAssertTrue(h.state.transientError?.isRateLimit ?? false)
    }

    func testASocketCloseWhileWaitingFailsTheMessageWithClosed() async {
        let h = EngineHarness()
        await h.startReady()
        await h.go { await $0.send("hi") }
        h.conn.serverClose(1006)
        await eventually("failed") { h.state.pending.first?.errorCode == "closed" }
    }

    func testEmptyTextIsIgnored() async {
        let h = EngineHarness()
        await h.startReady()
        await h.go { await $0.send("   ") }
        XCTAssertTrue(h.state.pending.isEmpty)
        XCTAssertFalse(h.conn.sentTypes.contains("message.send"))
    }

    func testTypingOneOnThenOffAfter3sIdle() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.onTextChanged("h")
        await h.engine.onTextChanged("he")
        await h.engine.onTextChanged("hel")
        await h.flush()
        XCTAssertEqual(h.conn.count("typing"), 1)
        await h.elapse(2_999)
        XCTAssertEqual(h.conn.count("typing"), 1)
        await h.elapse(1)
        XCTAssertEqual(h.conn.count("typing"), 2)
        XCTAssertEqual(h.conn.lastD("typing")["on"], false)
    }

    // MARK: - Incoming

    func testVisibleAndForegroundReadReceiptNoUnread() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.setVisible(true)
        h.conn.push(agentMessage(4))
        await eventually("received") { h.received.count == 1 }
        XCTAssertEqual(h.conn.lastD("read"), json(#"{"conversation_id":"conv_1","up_to_seq":4}"#))
        XCTAssertEqual(h.state.unread, 0)
        XCTAssertEqual(h.received.first?.seq, 4)
    }

    func testNotVisibleUnreadGrowsAndNoReadReceipt() async {
        let h = EngineHarness()
        await h.startReady()
        let before = h.state.unread
        h.conn.push(agentMessage(4))
        h.conn.push(agentMessage(5))
        await eventually("received") { h.received.count == 2 }
        XCTAssertFalse(h.conn.sentTypes.contains("read"))
        XCTAssertEqual(h.state.unread, before + 2)
        await h.engine.setVisible(true)
        XCTAssertEqual(h.state.unread, 0)
        XCTAssertEqual(h.conn.lastD("read"), json(#"{"conversation_id":"conv_1","up_to_seq":5}"#))
    }

    func testVisibleButBackgroundedUnreadGrows() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.setVisible(true)
        await h.engine.setForeground(false)
        let reads = h.conn.count("read")
        h.conn.push(agentMessage(4))
        await eventually("received") { h.received.count == 1 }
        XCTAssertEqual(h.conn.count("read"), reads)
        XCTAssertEqual(h.state.unread, 1)
    }

    func testMessagesForAnotherConversationAreIgnored() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(agentMessage(9, conversationId: "conv_other"))
        await h.flush()
        XCTAssertEqual(h.state.timeline.lastSeq, 3)
    }

    func testAgentTypingShowsAndAMessageClearsIt() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(json(#"{"t":"typing","d":{"conversation_id":"conv_1","side":"agent","on":true,"name":"Lan"}}"#))
        await eventually("typing") { h.state.typingAgent == "Lan" }
        h.conn.push(agentMessage(4))
        await eventually("cleared") { h.state.typingAgent == nil }
    }

    func testAgentReadStampsTheVisitorsMessages() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(json(#"{"t":"read","d":{"conversation_id":"conv_1","side":"agent","up_to_seq":3}}"#))
        await eventually("stamped") { h.state.timeline.items.first { $0.id == "m_1" }?.message?.readAt != nil }
        XCTAssertNil(h.state.timeline.items.first { $0.id == "m_3" }?.message?.readAt)
    }

    func testStatusChangedEventAndConversationUpdate() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(json(#"{"t":"event","d":{"kind":"event","id":"ev_9","conversation_id":"conv_1","seq":4,"type":"status_changed","data":{"to":"resolved"},"created_at":"2026-09-27T10:09:00.000Z"}}"#))
        await eventually("resolved") { h.state.conversation?.status == .resolved }
        XCTAssertEqual(h.statusEvents, [.resolved])
        h.conn.push(json(#"{"t":"conversation.update","d":{"id":"conv_1","status":"open","seq":5}}"#))
        await eventually("open") { h.state.conversation?.status == .open }
        XCTAssertEqual(h.state.conversation?.seq, 5)
        XCTAssertEqual(h.statusEvents.count, 2)
        h.conn.push(json(#"{"t":"event","d":{"kind":"event","id":"ev_10","conversation_id":"conv_1","seq":6,"type":"rated","data":{"score":4}}}"#))
        await eventually("rated") { h.state.rated == 4 }
    }

    func testUnsolicitedErrorFramesBecomeATransientErrorUnknownFramesAreIgnored() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(json(#"{"t":"future.frame","d":{"x":1}}"#))
        h.conn.push(json(#"{"t":"error","d":{"code":"conversation_closed","message":"closed"}}"#))
        await eventually("error") { h.state.transientError?.code == "conversation_closed" }
        XCTAssertEqual(h.state.connection, .connected)
        await h.engine.clearTransientError()
        XCTAssertNil(h.state.transientError)
    }

    func testOrderPaidReportsAPurchaseConversion() async {
        let h = EngineHarness()
        await h.startReady()
        let m = agentMessage(4)
        h.conn.push(m.with(["d": .object(m.d.with(["metadata": ["kind": "order_paid", "value": 150000, "code": "A1"]]))]))
        await eventually("conversion") { h.conversions.count == 1 }
        let c = h.conversions[0]
        XCTAssertEqual(c.kind, .purchase)
        XCTAssertEqual(c.data["value"], 150000)
        XCTAssertEqual(c.data["transaction_id"], "A1")
    }

    func testConversationStartAdoptsTheThreadReplaysItAndAsksToOpen() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = noConversation
        await h.startReady()
        h.conn.push(frame("conversation_start"))
        await eventually("adopted") { h.state.conversation?.id == "conv_2" }
        XCTAssertEqual(h.conn.lastD("resume"), json(#"{"conversation_id":"conv_2","after_seq":0}"#))
        await eventually("open request") { h.openRequests == ["conv_2"] }
        await eventually("stored") { h.prefs.values["hatang_chat.site_1.conversation_id"] == "conv_2" }
    }

    func testConversationStartWhileTheChatIsVisibleDoesNotReopenIt() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = noConversation
        await h.startReady()
        await h.engine.setVisible(true)
        h.conn.push(frame("conversation_start"))
        await eventually("adopted") { h.state.conversation?.id == "conv_2" }
        await h.flush()
        XCTAssertTrue(h.openRequests.isEmpty)
    }

    // MARK: - Session

    func testIdentifySendsTheSignedIdentityAndRemembersEmailAndName() async throws {
        let h = EngineHarness()
        await h.startReady()
        await h.go { try await $0.identify(HatangUser(userId: "u1", email: "an@x.test", name: "An", hash: "abc", data: ["plan": "pro"])) }
        let f = try XCTUnwrap(h.conn.lastOfType("identify"))
        XCTAssertEqual(f.d, json(#"{"user_id":"u1","email":"an@x.test","name":"An","hash":"abc","data":{"plan":"pro"}}"#))
        h.conn.push(json(#"{"t":"pong","id":"\#(f.s("id") ?? "")","d":{}}"#))
        await eventually("email remembered") { h.prefs.values["hatang_chat.site_1.email"] == "an@x.test" }
        XCTAssertEqual(h.state.visitorEmail, "an@x.test")
        XCTAssertEqual(h.state.session.name, "An")
    }

    func testIdentifyWithoutASocketThrowsClosed() async {
        let h = EngineHarness()
        do {
            try await h.engine.identify(HatangUser(userId: "u1"))
            XCTFail("expected closed")
        } catch {
            XCTAssertEqual((error as? HatangError)?.code, "closed")
        }
    }

    func testASessionFrameStoresTheNewTokenAndBootstrapsAgain() async throws {
        let h = EngineHarness()
        await h.startReady()
        await h.go { try await $0.identify(HatangUser(userId: "u1", hash: "h")) }
        let id = try XCTUnwrap(h.conn.lastOfType("identify")?["id"])
        h.conn.push(frame("session").with(["id": id]))
        h.conn.serverClose(CloseCodes.sessionReplaced)
        await eventually("bootstrapped with the merged token") { h.api.bootstraps.last?.token == "tok_merged" }
        await eventually("session changed") { h.sessionChanges.count == 1 }
        XCTAssertEqual(h.secure.values[tokenKey], "tok_merged")
        XCTAssertEqual(h.sessionChanges.first?.1, .identityMerged)
        XCTAssertEqual(h.sessionChanges.first?.0, "vis_2")
        await eventually("auth with the merged token") { h.conn.sent.first?.d.s("token") == "tok_merged" }
    }

    func testAuthFailedDropsTheTokenAndBootstrapsAFreshVisitor() async {
        let h = EngineHarness(secure: [tokenKey: "tok_old"])
        await h.startReady()
        h.conn.serverClose(CloseCodes.authFailed)
        await eventually("fresh visitor") { h.api.bootstraps.count == 2 && h.connector.connections.count == 2 }
        XCTAssertEqual(h.api.bootstraps.map(\.token), ["tok_old", nil])
        await eventually("event") { h.sessionChanges.count == 1 }
        XCTAssertEqual(h.secure.values[tokenKey], "tok_fresh")
        XCTAssertEqual(h.sessionChanges.first?.1, .tokenRejected)
        await eventually("auth") { h.conn.sent.first?.d.s("token") == "tok_fresh" }
    }

    func testProtocolOutdatedMarksTheSDKOutdatedAndStopsReconnecting() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.push(json(#"{"t":"reload","d":{"reason":"protocol_outdated"}}"#))
        await eventually("reload bootstraps again") { h.connector.connections.count == 2 && h.conn.sentTypes == ["auth"] }
        h.conn.serverClose(CloseCodes.protocolOutdated, "update")
        await eventually("outdated") { h.state.phase == .outdated }
        await h.elapse(300_000)
        XCTAssertEqual(h.state.connection, .outdated)
        XCTAssertEqual(h.state.outdatedReason, "update")
        XCTAssertEqual(h.outdatedEvents.count, 1)
        let connections = h.connector.connections.count
        await h.engine.setForeground(false)
        await h.engine.setForeground(true)
        await h.elapse(60_000)
        XCTAssertEqual(h.connector.connections.count, connections)
    }

    func testAuthTimeoutReconnectsWithBackoffAndAuthenticatesFirst() async {
        let h = EngineHarness()
        await h.startReady()
        h.conn.serverClose(CloseCodes.authTimeout)
        await h.flush()
        await h.elapse(500)
        await eventually("reconnected") { h.connector.connections.count == 2 && h.conn.sentTypes == ["auth"] }
        XCTAssertEqual(h.api.bootstraps.count, 1)
    }

    func testResetPostsResetDeletesTheDeviceUnderTheOldTokenAndReRegistersPush() async {
        let h = EngineHarness(secure: [tokenKey: "tok_old"])
        await h.startReady()
        await h.go { await $0.setPushToken("push_1", provider: .fcm) }
        await eventually("registered") { h.api.putDevices.count == 1 }
        await h.go { try await $0.reset() }
        await eventually("bootstrapped the new visitor") { h.api.bootstraps.last?.token == "tok_reset" }
        XCTAssertEqual(h.api.resets.first?.0, "tok_old")
        XCTAssertEqual(h.api.resets.first?.1, h.engine.installId)
        XCTAssertEqual(h.api.deleteDevices.map { "\($0.0)/\($0.1)" }, ["tok_old/push_1"])
        XCTAssertEqual(h.secure.values[tokenKey], "tok_reset")
        await readyAgain(h, connections: 2)
        await eventually("re-registered") { h.api.putDevices.count == 2 }
        await eventually("event") { h.sessionChanges.first?.1 == .reset }
    }

    func testResetBeforeStartForgetsTheStoredVisitorWithoutConnecting() async {
        let h = EngineHarness(secure: [tokenKey: "tok_old"])
        await h.go { try await $0.reset() }
        await eventually("reset") { h.secure.values[tokenKey] == "tok_reset" }
        XCTAssertEqual(h.api.resets.first?.0, "tok_old")
        XCTAssertTrue(h.api.bootstraps.isEmpty)
        XCTAssertTrue(h.connector.connections.isEmpty)
    }

    func testRestoreSessionSwapsTheLinkTokenAndBootstraps() async {
        let h = EngineHarness()
        await h.startReady()
        h.api.server.enqueue(.json(#"{"visitor_token":"tok_link","visitor_id":"vis_link","conversation_id":"conv_1"}"#))
        await h.go { try await $0.restoreSession("link_1") }
        await eventually("bootstrapped with the restored token") { h.api.bootstraps.last?.token == "tok_link" }
        await eventually("event") { h.sessionChanges.first?.1 == .restored }
        XCTAssertEqual(h.sessionChanges.first?.0, "vis_link")
        XCTAssertEqual(h.secure.values[tokenKey], "tok_link")
    }

    // MARK: - Lifecycle

    func testBackgroundAppStateFalseSocketClosedAfter10sForegroundReconnects() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.setVisible(true)
        await h.engine.setForeground(false)
        XCTAssertEqual(h.conn.lastD("app.state"), json(#"{"foreground":false,"conversation_id":null}"#))
        await h.elapse(9_000)
        XCTAssertFalse(h.conn.isClosed)
        await h.elapse(1_000)
        await eventually("closed") { h.conn.isClosed }
        XCTAssertEqual(h.state.connection, .disconnected)
        await h.elapse(300_000)
        XCTAssertEqual(h.connector.connections.count, 1, "no reconnect while backgrounded")

        await h.engine.setForeground(true)
        await eventually("reconnecting") { h.connector.connections.count == 2 && !h.conn.sentRaw.isEmpty }
        XCTAssertEqual(h.conn.sent.first?.d.obj("app_state")?["foreground"], true)
        h.conn.push(FakeSocketConnection.readyFrame())
        await eventually("connected") { h.state.connection == .connected }
        await h.flush()
        XCTAssertEqual(h.conn.lastD("app.state"), json(#"{"foreground":true,"conversation_id":"conv_1"}"#))
        XCTAssertNotNil(h.conn.lastOfType("resume"))
    }

    func testAQuickReturnKeepsTheSocketAndReportsForeground() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.setForeground(false)
        await h.elapse(3_000)
        await h.engine.setForeground(true)
        await h.elapse(30_000)
        XCTAssertEqual(h.connector.connections.count, 1)
        XCTAssertFalse(h.conn.isClosed)
        XCTAssertEqual(h.conn.lastD("app.state"), json(#"{"foreground":true,"conversation_id":null}"#))
    }

    func testStopClosesTheSocketAndConnectBringsItBack() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.stop()
        await eventually("closed") { h.conn.isClosed }
        XCTAssertFalse(h.engine.isStarted)
        XCTAssertEqual(h.state.connection, .disconnected)
        await h.elapse(60_000)
        XCTAssertEqual(h.connector.connections.count, 1)
        await h.go { await $0.connect() }
        await eventually("back") { h.connector.connections.count == 2 && h.api.bootstraps.count == 2 }
    }

    func testDisposeStopsEverything() async {
        let h = EngineHarness()
        await h.startReady()
        var states: [ChatState] = []
        let stream = h.engine.states()
        await h.engine.dispose()
        for await s in stream { states.append(s) }
        XCTAssertFalse(states.isEmpty, "the state stream finishes on dispose")
        await eventually("closed") { h.conn.isClosed }
        await h.elapse(60_000)
        XCTAssertEqual(h.connector.connections.count, 1)
        await h.go { await $0.send("after dispose") }
        XCTAssertFalse(h.conn.sentTypes.contains("message.send"))
    }

    func testStatesStreamStartsWithTheCurrentValue() async {
        let h = EngineHarness()
        await h.startReady()
        var it = h.engine.states().makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first?.phase, .ready)
        XCTAssertEqual(first, h.state)
        await h.engine.setVisible(true)
        let next = await it.next()
        XCTAssertEqual(next?.visible, true)
    }

    // MARK: - Offline form

    func testAwayAndEmailWantedThePreChatFormHoldsTheDraft() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = { offline()(noConversation($0)) }
        await h.startReady()
        h.conn.push(awayFrame)
        await eventually("away") { !h.state.online }
        await h.go { await $0.send("need help") }
        XCTAssertTrue(h.state.needsEmail)
        XCTAssertEqual(h.state.draft, "need help")
        XCTAssertFalse(h.conn.sentTypes.contains("message.send"))

        await h.go { await $0.submitOfflineForm(name: "An", email: "an@x.test") }
        await eventually("submitted") { h.state.conversation?.id == "conv_off" }
        await eventually("notice") { h.state.timeline.items.last?.event?.type == "notice" }
        XCTAssertEqual(h.api.offlineMessages, [OfflineCall(message: "need help", name: "An", email: "an@x.test")])
        XCTAssertFalse(h.state.needsEmail)
        XCTAssertEqual(h.state.visitorEmail, "an@x.test")
        XCTAssertNil(h.state.draft)
        XCTAssertEqual(h.conversions.map(\.kind), [.chatStarted])
    }

    func testSkippingTheOptionalEmailSendsTheDraftOverTheSocket() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = { offline()(noConversation($0)) }
        await h.startReady()
        h.conn.push(awayFrame)
        await eventually("away") { !h.state.online }
        await h.go { await $0.send("hello") }
        await h.go { await $0.skipEmail() }
        XCTAssertFalse(h.state.needsEmail)
        XCTAssertEqual(h.conn.lastD("message.send").s("content"), "hello")
    }

    func testSubmittingAnInlineEmailIdentifiesAndSendsTheDraft() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = { offline("email_required")(noConversation($0)) }
        await h.startReady()
        h.conn.push(awayFrame)
        await eventually("away") { !h.state.online }
        await h.go { await $0.send("hello") }
        await h.go { await $0.submitEmail(" an@x.test ") }
        XCTAssertEqual(h.conn.lastD("identify"), json(#"{"email":"an@x.test"}"#))
        await eventually("draft sent") { h.conn.lastD("message.send").s("content") == "hello" }
        XCTAssertEqual(h.prefs.values["hatang_chat.site_1.email"], "an@x.test")
    }

    func testOfflineCaptureOffSendsStraightAway() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = offline("off")
        await h.startReady()
        h.conn.push(awayFrame)
        await eventually("away") { !h.state.online }
        await h.go { await $0.send("hello") }
        XCTAssertFalse(h.state.needsEmail)
        XCTAssertNotNil(h.conn.lastOfType("message.send"))
    }

    func testCancelEmailFormDropsTheDraft() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = { offline()(noConversation($0)) }
        await h.startReady()
        h.conn.push(awayFrame)
        await eventually("away") { !h.state.online }
        await h.go { await $0.send("hello") }
        await h.engine.cancelEmailForm()
        XCTAssertFalse(h.state.needsEmail)
        XCTAssertNil(h.state.draft)
    }

    // MARK: - Push

    func testPushRegistrationIsDeferredUntilTheSocketIsReady() async throws {
        let h = EngineHarness(secure: [tokenKey: "tok_saved"])
        await h.go { await $0.setPushToken("push_1", provider: .apns) }
        XCTAssertTrue(h.api.putDevices.isEmpty)
        // The stored token survives a push token set before start.
        XCTAssertEqual(h.secure.values[tokenKey], "tok_saved")

        await h.go { await $0.start() }
        await eventually("auth") { !h.connector.connections.isEmpty && h.conn.sentTypes == ["auth"] }
        XCTAssertEqual(h.api.bootstraps.map(\.token), ["tok_saved"])
        XCTAssertTrue(h.api.putDevices.isEmpty)
        h.conn.push(FakeSocketConnection.readyFrame())
        await eventually("registered") { h.api.putDevices.count == 1 }
        let d = h.api.putDevices[0]
        XCTAssertEqual(d.s("token"), "push_1")
        XCTAssertEqual(d.s("provider"), "apns")
        XCTAssertEqual(d.s("platform"), "ios")
        XCTAssertEqual(d.s("app_version"), "1.0.0+1")
        XCTAssertEqual(d.s("install_id"), h.engine.installId)

        // Same token again: no second PUT; reconnect: no second PUT.
        await h.go { await $0.setPushToken("push_1", provider: .apns) }
        h.conn.serverClose(1006)
        await h.flush()
        await h.elapse(500)
        await readyAgain(h, connections: 2)
        XCTAssertEqual(h.api.putDevices.count, 1)

        // A new token registers again.
        await h.go { await $0.setPushToken("push_2", provider: .apns) }
        await eventually("re-registered") { h.api.putDevices.last?.s("token") == "push_2" }
    }

    func testClearPushTokenDeletesTheDevice() async {
        let h = EngineHarness()
        await h.startReady()
        await h.go { await $0.setPushToken(apnsDeviceToken: Data([0xab, 0x01])) }
        await eventually("registered") { h.api.putDevices.first?.s("token") == "ab01" }
        XCTAssertEqual(h.api.putDevices.first?.s("provider"), "apns")
        await h.go { await $0.clearPushToken() }
        await eventually("deleted") { h.api.deleteDevices.count == 1 }
        XCTAssertEqual(h.api.deleteDevices.first?.0, "tok_fresh")
        XCTAssertEqual(h.api.deleteDevices.first?.1, "ab01")
        XCTAssertNil(h.prefs.values["hatang_chat.site_1.push_token"])
    }

    // MARK: - Misc

    func testShowLocalMessageAddsABotBubbleThatIsNeverSent() async throws {
        let h = EngineHarness()
        await h.startReady()
        let before = h.conn.sentRaw.count
        await h.engine.showLocalMessage("Hello from the app", senderName: "Bot")
        let last = try XCTUnwrap(h.state.timeline.items.last?.message)
        XCTAssertEqual(last.content, "Hello from the app")
        XCTAssertEqual(last.senderType, .bot)
        XCTAssertEqual(last.senderName, "Bot")
        XCTAssertTrue(TimelineItem.message(last).isLocal)
        XCTAssertEqual(h.conn.sentRaw.count, before)
        await h.flush()
        XCTAssertEqual(h.prefs.values["hatang_chat.site_1.last_seq"], "3")
    }

    func testSetLocalePersistsAndReAuthenticates() async {
        let h = EngineHarness()
        await h.startReady()
        XCTAssertEqual(h.state.locale, .vi)
        await h.go { await $0.setLocale(.en) }
        XCTAssertEqual(h.state.locale, .en)
        XCTAssertEqual(h.prefs.values["hatang_chat.site_1.locale"], "en")
        await eventually("re-authenticated") { h.connector.connections.count == 2 && !h.conn.sentRaw.isEmpty }
        XCTAssertEqual(h.conn.sent.first?.d.s("locale"), "en")
    }

    func testScreenRateAndPushEventFrames() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.setScreen("checkout", params: ["step": "2"])
        await h.engine.rate(5, comment: "great")
        await h.engine.pushEvent("viewed", data: ["sku": "A1"])
        XCTAssertEqual(h.conn.lastD("screen"), json(#"{"name":"checkout","params":{"step":"2"}}"#))
        XCTAssertEqual(h.conn.lastD("rate"), json(#"{"conversation_id":"conv_1","score":5,"comment":"great"}"#))
        XCTAssertEqual(h.state.rated, 5)
        XCTAssertEqual(h.conn.lastD("event"), json(#"{"name":"viewed","data":{"sku":"A1"}}"#))
        // The screen rides along on the next auth too.
        h.conn.serverClose(1006)
        await h.flush()
        await h.elapse(500)
        await eventually("auth") { h.connector.connections.count == 2 && !h.conn.sentRaw.isEmpty }
        XCTAssertEqual(h.conn.sent.first?.d["screen"], .object(json(#"{"name":"checkout","params":{"step":"2"}}"#)))
    }

    func testLoadEarlierPagesWithBeforeSeqEqualToOldestSeq() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = { $0.with(["timeline": [.object(frame("message").d.with(["id": "m_60", "seq": 60]))]]) }
        await h.startReady()
        XCTAssertTrue(h.state.timeline.hasMore)
        await h.go { await $0.loadEarlier() }
        await eventually("loaded") { !h.state.timeline.hasMore }
        XCTAssertEqual(h.api.messageCalls, [MessagesCall(before: 60, after: nil, limit: 50)])
    }

    private func greeted(_ seq: Int) -> JSONValue {
        .object(frame("message").d.with(["id": .string("m_\(seq)"), "seq": .number(Double(seq))]))
    }

    func testBootstrapTheGatewaySayingNothingIsOlderWinsOverAFirstSeqPast1() async {
        let h = EngineHarness()
        let g = greeted(4)
        h.api.bootstrapEdit = { $0.with(["timeline": [g], "timeline_has_more": false]) }
        await h.startReady()
        XCTAssertEqual(h.state.timeline.oldestSeq, 4)
        XCTAssertFalse(h.state.timeline.hasMore)
    }

    func testReadySwitchingToAnotherConversationFollowsTheGatewayToo() async {
        let h = EngineHarness()
        h.api.bootstrapEdit = noConversation
        let ready = FakeSocketConnection.readyFrame()
        await h.startReady(ready.with(["d": .object(ready.d.with([
            "conversation": bootstrapFixture()["conversation"]!,
            "timeline": [greeted(5)],
            "timeline_has_more": false,
        ]))]))
        XCTAssertEqual(h.state.timeline.oldestSeq, 5)
        XCTAssertFalse(h.state.timeline.hasMore)
    }

    func testAnOlderGatewayThatDoesNotSayGuessedFromTheFirstSeq() async {
        let h = EngineHarness()
        let g = greeted(4)
        h.api.bootstrapEdit = { $0.with(["timeline": [g]]) }
        await h.startReady()
        XCTAssertTrue(h.state.timeline.hasMore)
    }

    // MARK: - Attachments

    private let photo = UploadSource(data: Data([1, 2, 3, 4, 5, 6, 7, 8]), name: "IMG_1.jpg", mimeType: "image/jpeg")

    func testUploadsThenSendsTheFileIdAndTheAckKeepsTheAttachment() async throws {
        let h = EngineHarness()
        await h.startReady()
        h.api.closeUploadGate()
        let photo = self.photo
        await h.go { await $0.attach(photo, caption: "Ảnh sản phẩm") }
        await eventually("uploading") { h.api.uploads.count == 1 }
        let p = try XCTUnwrap(h.state.pending.first)
        XCTAssertEqual(p.upload?.source.name, "IMG_1.jpg")
        XCTAssertLessThan(p.upload?.progress ?? 1, 1)
        XCTAssertEqual(p.upload?.done, false)
        XCTAssertNil(h.conn.lastOfType("message.send"), "not before the bytes are up")
        h.api.openUploadGate()
        await eventually("sent") { h.conn.lastOfType("message.send") != nil }
        let send = h.conn.lastD("message.send")
        XCTAssertEqual(send["attachments"], ["file_1"])
        XCTAssertEqual(send.s("content"), "Ảnh sản phẩm")
        XCTAssertEqual(h.api.uploads, [UploadCall(filename: "IMG_1.jpg", contentType: "image/jpeg", size: 8)])
        XCTAssertEqual(h.state.pending.first?.upload?.progress, 1)
        await h.ack(id: "m_img")
        await eventually("acked") { h.state.pending.isEmpty }
        let m = try XCTUnwrap(h.state.timeline.items.compactMap(\.message).first { $0.id == "m_img" })
        XCTAssertEqual(m.attachments.map(\.id), ["file_1"])
        XCTAssertTrue(m.attachments[0].isImage)
    }

    func testRefusesFilesOver10MBAndTypesTheGatewayWouldRejectWithoutUploading() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.attach(UploadSource(data: Data(count: Limits.attachmentBytes + 1), name: "big.pdf", mimeType: "application/pdf"))
        XCTAssertEqual(h.state.transientError?.code, "file_too_large")
        await h.engine.attach(UploadSource(data: Data([1]), name: "x.exe", mimeType: "application/x-msdownload"))
        XCTAssertEqual(h.state.transientError?.code, "unsupported_file_type")
        XCTAssertTrue(h.api.uploads.isEmpty)
        XCTAssertTrue(h.state.pending.isEmpty)
    }

    func testAFailedUploadFailsTheBubbleRetryUploadsAgainThenSends() async throws {
        let h = EngineHarness()
        await h.startReady()
        h.api.uploadError = .json(#"{"statusCode":429,"name":"rate_limit_exceeded","message":"slow down"}"#, status: 429)
        let photo = self.photo
        await h.go { await $0.attach(photo) }
        await eventually("failed") { h.state.pending.first?.failed == true }
        let failed = try XCTUnwrap(h.state.pending.first)
        XCTAssertEqual(failed.errorCode, "rate_limit_exceeded")
        XCTAssertNil(h.conn.lastOfType("message.send"))
        await h.go { await $0.retry(failed.clientId) }
        await eventually("sent") { h.conn.lastOfType("message.send") != nil }
        XCTAssertEqual(h.api.uploads.count, 2)
        let send = h.conn.lastD("message.send")
        XCTAssertEqual(send.s("client_id"), failed.clientId)
        XCTAssertEqual(send["attachments"], ["file_2"])
    }

    func testWhenOnlyTheSendFailedRetryDoesNotUploadAgain() async throws {
        let h = EngineHarness()
        await h.startReady()
        let photo = self.photo
        await h.go { await $0.attach(photo) }
        await eventually("sent") { h.conn.lastOfType("message.send") != nil }
        await h.elapse(11_000) // no ack: the send times out
        await eventually("failed") { h.state.pending.first?.failed == true }
        let failed = try XCTUnwrap(h.state.pending.first)
        XCTAssertEqual(failed.upload?.done, true)
        await h.go { await $0.retry(failed.clientId) }
        await eventually("sent again") { h.conn.count("message.send") == 2 }
        XCTAssertEqual(h.api.uploads.count, 1)
        XCTAssertEqual(h.conn.lastD("message.send")["attachments"], ["file_1"])
    }

    func testAnExpiredLinkRefetchesThatOneMessageOnce() async {
        let h = EngineHarness()
        await h.startReady()
        let m = MessageDto(id: "m_3", conversationId: "conv_1", seq: 3, senderType: .agent)
        await h.engine.refreshAttachments(m)
        await h.engine.refreshAttachments(m)
        XCTAssertEqual(h.api.messageCalls, [MessagesCall(before: nil, after: 2, limit: 1)])
    }

    // MARK: - History

    private func conv(_ id: String, _ status: ConversationStatus, seq: Int = 7) -> VisitorConversationDto {
        VisitorConversationDto(id: id, status: status, seq: seq)
    }

    private func msg(_ id: String, _ seq: Int, _ conversationId: String) -> TimelineItem {
        .message(MessageDto(
            id: id,
            conversationId: conversationId,
            seq: seq,
            senderType: .agent,
            content: "old \(seq)",
            createdAt: Date(timeIntervalSince1970: 1_788_256_800 + Double(seq * 60))
        ))
    }

    func testOpensAnOlderConversationLatestPageFocusAndAReadReceipt() async {
        let h = EngineHarness()
        await h.startReady()
        await h.engine.setVisible(true)
        h.api.setMessagesItems([msg("o1", 1, "conv_old"), msg("o2", 2, "conv_old")])
        let summary = conv("conv_old", .resolved, seq: 2)
        await h.go { await $0.openConversation("conv_old", summary: summary) }
        await eventually("loaded") { h.state.timeline.items.map(\.id) == ["o1", "o2"] }
        await h.flush()
        XCTAssertEqual(h.state.conversation?.id, "conv_old")
        XCTAssertEqual(h.state.conversation?.status, .resolved)
        XCTAssertEqual(h.api.messageCalls.last, MessagesCall(before: 3, after: nil, limit: 50))
        XCTAssertEqual(h.conn.lastD("app.state").s("conversation_id"), "conv_old")
        XCTAssertEqual(h.conn.lastD("read"), json(#"{"conversation_id":"conv_old","up_to_seq":2}"#))
        // A resolved thread is not the one resumed after a restart.
        XCTAssertFalse(h.prefs.values.values.contains("conv_old"))
        // Live messages of the thread on screen merge; others do not.
        h.conn.push(agentMessage(3, conversationId: "conv_old"))
        h.conn.push(agentMessage(9))
        await eventually("merged") { h.state.timeline.items.count == 3 }
        await h.flush()
        XCTAssertEqual(h.state.timeline.items.map(\.id), ["o1", "o2", "m_3"])
    }

    func testAConversationAskedForBeforeReadyOpensOnceTheSessionIsReady() async {
        let h = EngineHarness()
        await h.go { await $0.openConversation("conv_later") }
        h.api.setMessagesItems([msg("l1", 1, "conv_later")])
        await h.startReady()
        await eventually("opened") { h.state.conversation?.id == "conv_later" && h.state.timeline.items.map(\.id) == ["l1"] }
        XCTAssertEqual(h.api.messageCalls.last, MessagesCall(before: Int(Int32.max), after: nil, limit: 50))
    }

    func testOpenActiveGoesBackToTheOpenConversationOrToAnEmptyChat() async {
        let h = EngineHarness()
        await h.startReady()
        h.api.setConversationPages([
            ConversationPage(conversations: [conv("conv_1", .open)], hasMore: false),
            ConversationPage(conversations: [], hasMore: false),
        ])
        h.api.setMessagesItems([msg("o1", 1, "conv_old")])
        let summary = conv("conv_old", .resolved)
        await h.go { await $0.openConversation("conv_old", summary: summary) }
        await eventually("old opened") { h.state.timeline.items.map(\.id) == ["o1"] }
        h.api.setMessagesItems([msg("a1", 1, "conv_1")])
        await h.go { try await $0.openActive() }
        await eventually("back to the open one") { h.state.conversation?.id == "conv_1" && h.state.timeline.items.map(\.id) == ["a1"] }
        XCTAssertEqual(h.api.listCalls.first?.0, "open")
        await h.go { try await $0.openActive() }
        await eventually("empty chat") { h.state.conversation == nil }
        XCTAssertTrue(h.state.timeline.items.isEmpty)
    }

    func testListConversationsReturnsTheGatewayPage() async throws {
        let h = EngineHarness()
        await h.startReady()
        h.api.setConversationPages([ConversationPage(conversations: [conv("c9", .resolved)], hasMore: true)])
        let page = try await h.engine.listConversations(status: "resolved")
        XCTAssertEqual(page.conversations.map(\.id), ["c9"])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(h.api.listCalls.map(\.0), ["resolved"])
        XCTAssertNil(h.api.listCalls.first?.1)
    }

    // MARK: - Real time, real HTTP stack

    func testBootstrapOverHTTPAuthSendWithAckPushRegistrationOnTheSystemClock() async throws {
        let server = StubServer()
        server.setHandler { r in
            if r.path == "/widget/v1/sites/site_1/bootstrap" {
                return .json(bootstrapFixture().with(["visitor_token": "tok_http", "conversation": nil, "timeline": []]))
            }
            if r.path == "/widget/v1/sites/site_1/devices" { return .json(#"{"ok":true}"#) }
            return .json(#"{"statusCode":404,"name":"not_found","message":"no"}"#, status: 404)
        }
        let connector = FakeConnector()
        let info = HatangAppInfo(appVersion: "2.0.0", osVersion: "18.1", deviceModel: "iPhone15,2", deviceLocale: "en-US")
        let engine = ChatEngine(
            api: WidgetAPI(baseURL: "https://gw.test/", siteId: "site_1", appKey: "hak_test", userAgent: info.userAgent, session: server.session),
            connector: connector,
            store: SessionStore(siteId: "site_1", secure: InMemoryKeyValueStore(), prefs: InMemoryKeyValueStore()),
            appInfo: info
        )
        await engine.start()
        let boot = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(boot.header("x-hatang-app-key"), "hak_test")
        let ua = try XCTUnwrap(boot.header("user-agent"))
        XCTAssertNotNil(ua.range(of: #"^hatang-chat-ios/[^ ]+ \(ios/18\.1; protocol/1\)$"#, options: .regularExpression), ua)
        let app = try XCTUnwrap(boot.json.obj("app"))
        XCTAssertEqual(app.s("os"), "ios")
        XCTAssertTrue(app.s("sdk")?.hasPrefix("ios/") ?? false)
        XCTAssertEqual(app.s("locale"), "en")

        await eventually("auth sent") { !connector.connections.isEmpty && connector.last.sentTypes == ["auth"] }
        XCTAssertEqual(connector.last.sent.first?.d.s("token"), "tok_http")
        connector.last.push(FakeSocketConnection.readyFrame())
        for await s in engine.states() where s.connection == .connected { break }

        let sending = Task { await engine.send("Hello") }
        await eventually("message.send sent") { connector.last.lastOfType("message.send") != nil }
        let f = try XCTUnwrap(connector.last.lastOfType("message.send"))
        connector.last.push(json(#"{"t":"message.ack","id":"\#(f.s("id") ?? "")","d":{"client_id":"\#(f.d.s("client_id") ?? "")","id":"m_1","seq":1,"conversation_id":"conv_9"}}"#))
        await sending.value
        XCTAssertTrue(engine.currentState.pending.isEmpty)
        XCTAssertEqual(engine.currentState.conversation?.id, "conv_9")

        await engine.setPushToken("apns_1", provider: .apns)
        let put = try XCTUnwrap(server.requests(path: "/devices", method: "PUT").first)
        XCTAssertEqual(put.header("x-visitor-token"), "tok_http")
        XCTAssertEqual(put.json.s("token"), "apns_1")
        XCTAssertEqual(put.json.s("provider"), "apns")
        XCTAssertEqual(put.json.s("platform"), "ios")
        XCTAssertEqual(put.json.s("device_model"), "iPhone15,2")
        await engine.dispose()
    }
}

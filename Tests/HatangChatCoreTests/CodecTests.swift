import XCTest
@testable import HatangChatCore

final class CodecTests: XCTestCase {
    private func decode(_ name: String) throws -> ServerFrame {
        try decodeFrame(Fixtures.text(name))
    }

    func testEveryFrameFixtureDecodesToTheFrameItsTNames() throws {
        let files = Fixtures.frameFiles
        XCTAssertGreaterThanOrEqual(files.count, 16, "fixtures found in \(Fixtures.directory.path)")
        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let f = try decodeFrame(raw)
            let t = JSONValue.parse(raw)?.objectValue?.t
            XCTAssertEqual(f.t, t, file.lastPathComponent)
            if case .unknown = f {
                XCTAssertEqual(file.lastPathComponent, "unknown.json")
            } else {
                XCTAssertNotEqual(file.lastPathComponent, "unknown.json")
            }
        }
    }

    func testReady() throws {
        guard case .ready(let f) = try decode("ready") else { return XCTFail("not ready") }
        XCTAssertEqual(f.visitor.id, "vis_1")
        XCTAssertEqual(f.visitor.client, "app")
        XCTAssertEqual(f.visitor.app?.platform, "flutter")
        XCTAssertEqual(f.visitor.locale, .vi)
        XCTAssertEqual(f.visitor.raw["device"]?.stringValue, "iPhone")
        XCTAssertEqual(f.conversation?.id, "conv_1")
        XCTAssertEqual(f.conversation?.status, .open)
        XCTAssertEqual(f.conversation?.lastMessageSenderType, .agent)
        XCTAssertEqual(f.timeline.count, 3)
        XCTAssertNotNil(f.timeline[0].message)
        XCTAssertNotNil(f.timeline[1].event)
        XCTAssertEqual(f.timeline[0].message?.clientId, "c1")
        XCTAssertTrue(f.availability.online)
        XCTAssertNil(f.timelineHasMore)
    }

    func testReadyWithoutAConversation() throws {
        guard case .ready(let f) = try decode("ready_empty") else { return XCTFail("not ready") }
        XCTAssertNil(f.conversation)
        XCTAssertTrue(f.timeline.isEmpty)
    }

    func testMessage() throws {
        guard case .message(let f) = try decode("message") else { return XCTFail() }
        XCTAssertEqual(f.message.seq, 4)
        XCTAssertEqual(f.message.senderType, .agent)
        XCTAssertFalse(f.message.isMine)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.hour, from: f.message.createdAt), 10)
    }

    func testMessageAckEchoesTheId() throws {
        guard case .messageAck(let f) = try decode("message_ack") else { return XCTFail() }
        XCTAssertEqual(f.id, "r1")
        XCTAssertEqual(f.clientId, "c1")
        XCTAssertEqual(f.messageId, "m_1")
        XCTAssertEqual(f.seq, 1)
        XCTAssertEqual(f.conversationId, "conv_1")
    }

    func testEvent() throws {
        guard case .event(let f) = try decode("event") else { return XCTFail() }
        XCTAssertEqual(f.event.type, "status_changed")
        XCTAssertEqual(f.event.data.str("to"), "resolved")
    }

    func testTypingAvailabilityReadPongReload() throws {
        guard case .typing(let t) = try decode("typing") else { return XCTFail() }
        XCTAssertTrue(t.on)
        XCTAssertEqual(t.name, "Lan")
        guard case .availability(let a) = try decode("availability") else { return XCTFail() }
        XCTAssertFalse(a.availability.online)
        XCTAssertNotNil(a.availability.nextOpenAt)
        guard case .read(let r) = try decode("read") else { return XCTFail() }
        XCTAssertEqual(r.upToSeq, 1)
        XCTAssertEqual(r.side, "agent")
        guard case .pong(let p) = try decode("pong") else { return XCTFail() }
        XCTAssertNotNil(p.now)
        guard case .reload(let rl) = try decode("reload") else { return XCTFail() }
        XCTAssertEqual(rl.reason, "identity merged")
    }

    func testResumeCarriesItemsWithCards() throws {
        guard case .resume(let f) = try decode("resume") else { return XCTFail() }
        XCTAssertEqual(f.id, "r2")
        XCTAssertFalse(f.hasMore)
        XCTAssertEqual(f.items.count, 1)
        guard case .quickReplies = cardOf(f.items[0].message?.metadata) else { return XCTFail("no quick replies") }
    }

    func testConversationStartAndUpdate() throws {
        guard case .conversationStart(let s) = try decode("conversation_start") else { return XCTFail() }
        XCTAssertEqual(s.conversation.id, "conv_2")
        XCTAssertTrue(s.open)
        guard case .conversationUpdate(let u) = try decode("conversation_update") else { return XCTFail() }
        XCTAssertEqual(u.conversation.status, .resolved)
        XCTAssertEqual(u.conversation.agent?.name, "Lan")
    }

    func testSessionAndError() throws {
        guard case .session(let s) = try decode("session") else { return XCTFail() }
        XCTAssertEqual(s.id, "r3")
        XCTAssertEqual(s.visitorToken, "tok_merged")
        XCTAssertEqual(s.reason, "identity_merged")
        guard case .error(let e) = try decode("error") else { return XCTFail() }
        XCTAssertEqual(e.code, "rate_limit_exceeded")
        XCTAssertEqual(e.id, "r4")
    }

    func testUnknownTIsTolerated() throws {
        guard case .unknown(let f) = try decode("unknown") else { return XCTFail() }
        XCTAssertEqual(f.t, "home.dirty")
        XCTAssertNotNil(f.d?.objectValue)
    }

    func testAgentStyleReadyWithoutAvailabilityIsUnknown() throws {
        guard case .unknown = try decodeFrame(#"{"t":"ready","d":{"user_id":"u1","team_id":"t1","agents":[]}}"#) else { return XCTFail() }
    }

    func testBadJSONThrowsDecodeErrorAndTryDecodeFrameReturnsNil() {
        XCTAssertThrowsError(try decodeFrame("{nope")) { e in
            XCTAssertEqual((e as? HatangError)?.code, "decode_error")
        }
        XCTAssertNil(tryDecodeFrame("[1,2]"))
        XCTAssertNil(tryDecodeFrame("not json"))
    }

    func testLenientDecodingSurvivesUnknownEnumsNullsWrongTypesAndJunkItems() throws {
        let raw = """
        {"t":"ready","d":{
          "visitor":{"id":"v","locale":"fr","client":null,"visits":"3","brand_new_field":{"x":1}},
          "conversation":{"id":"c","status":"archived","seq":"7","last_message_sender_type":"robot"},
          "timeline":[
            {"kind":"message","id":"m1","conversation_id":"c","seq":1,"sender_type":"alien","content":"hi","attachments":[1,{"id":"f","size":"12"}],"metadata":"oops","created_at":"not a date"},
            "junk", 42,
            {"id":"e2","conversation_id":"c","seq":2,"type":"brand_new_event","data":[1,2]}
          ],
          "availability":{"online":true,"within_hours":null}}}
        """
        guard case .ready(let f) = try decodeFrame(raw) else { return XCTFail() }
        XCTAssertNil(f.visitor.locale)
        XCTAssertEqual(f.visitor.client, "app")
        XCTAssertEqual(f.visitor.visits, 3)
        XCTAssertEqual(f.conversation?.status, .unknown)
        XCTAssertEqual(f.conversation?.seq, 7)
        XCTAssertEqual(f.conversation?.lastMessageSenderType, .system)
        XCTAssertEqual(f.timeline.count, 2)
        let m = try XCTUnwrap(f.timeline[0].message)
        XCTAssertEqual(m.senderType, .system)
        XCTAssertEqual(m.attachments.count, 1)
        XCTAssertEqual(m.attachments[0].size, 12)
        XCTAssertNil(m.metadata)
        XCTAssertEqual(m.createdAt, Date(timeIntervalSince1970: 0))
        let e = try XCTUnwrap(f.timeline[1].event)
        XCTAssertEqual(e.type, "brand_new_event")
        XCTAssertTrue(e.data.isEmpty)
        XCTAssertTrue(f.availability.withinHours)
    }

    func testAPayloadThatDoesNotFitDoesNotCrash() throws {
        let f = try decodeFrame(#"{"t":"message","d":{"id":{"nested":true},"seq":[1]}}"#)
        switch f {
        case .message(let m): XCTAssertEqual(m.message.seq, 0)
        case .unknown: break
        default: XCTFail("unexpected \(f)")
        }
    }

    func testFixturesRoundTripThroughToJSON() throws {
        guard case .ready(let ready) = try decode("ready") else { return XCTFail() }
        for item in ready.timeline {
            let again = TimelineItem(json: item.toJSON())
            XCTAssertEqual(item, again)
            XCTAssertEqual(item.toJSON().str("kind"), item.kind)
        }
        guard case .message(let mf) = try decode("message") else { return XCTFail() }
        let m = mf.message
        XCTAssertEqual(m.toJSON().str("kind"), "message")
        XCTAssertEqual(m.toJSON().str("created_at"), "2026-09-27T10:04:00.000Z")
        XCTAssertEqual(TimelineItem(json: m.toJSON()).message?.content, m.content)
        guard case .event(let ef) = try decode("event") else { return XCTFail() }
        XCTAssertEqual(TimelineItem(json: ef.event.toJSON()).event?.type, ef.event.type)
        let v = ready.visitor
        XCTAssertEqual(v.toJSON().str("device"), "iPhone")
        var withRaw = v
        withRaw.raw = v.toJSON()
        XCTAssertEqual(VisitorDto(json: v.toJSON()), withRaw)
    }

    func testCodableUsesTheWireShape() throws {
        guard case .message(let mf) = try decode("message") else { return XCTFail() }
        let data = try JSONEncoder().encode(mf.message)
        let back = try JSONDecoder().decode(MessageDto.self, from: data)
        XCTAssertEqual(back, mf.message)
        let o = try XCTUnwrap(JSONValue.parse(data)?.objectValue)
        XCTAssertEqual(o.str("conversation_id"), mf.message.conversationId)
        XCTAssertEqual(o.str("sender_type"), "agent")
        let status = try JSONDecoder().decode([ConversationStatus].self, from: Data(#"["open","archived"]"#.utf8))
        XCTAssertEqual(status, [.open, .unknown])
    }

    func testBootstrapFixture() {
        let b = BootstrapResponse(json: bootstrapFixture())
        XCTAssertEqual(b.visitorToken, "tok_1")
        XCTAssertEqual(b.conversation?.id, "conv_1")
        XCTAssertEqual(b.timeline.count, 3)
        XCTAssertTrue(b.wsUrl.hasPrefix("ws://"))
        XCTAssertEqual(b.appId, "app_1")
        XCTAssertEqual(b.config.offlineCapture, .emailOptional)
        XCTAssertEqual(b.config.greetingFor(.vi), "Xin chào!")
        XCTAssertEqual(b.config.agentAvatars.map(\.name), ["Lan"])
        XCTAssertNotNil(b.config.raw["campaigns"])
        XCTAssertEqual(b.config.launcher.icon, .chat)
    }

    func testEncodeAddsVAndId() {
        let j = json(encodeFrame(.resume(conversationId: "c", afterSeq: 3), id: "x1"))
        XCTAssertEqual(j.t, "resume")
        XCTAssertEqual(j.int("v"), protocolVersion)
        XCTAssertEqual(j.str("id"), "x1")
        XCTAssertEqual(j.d, json(#"{"conversation_id":"c","after_seq":3}"#))
    }

    func testPingHasNoPayload() {
        let j = json(encodeFrame(.ping()))
        XCTAssertEqual(j.t, "ping")
        XCTAssertNil(j["d"])
    }

    func testAuthOmitsAbsentFields() {
        let j = json(encodeFrame(.auth(
            token: "t",
            siteId: "s",
            app: AppContext(installId: "ins_12345678", sdk: "ios/0.1.0"),
            client: ClientInfo(sdk: "ios", version: "0.1.0"),
            foreground: false
        )))
        XCTAssertEqual(Set(j.d.keys), ["token", "site_id", "app", "client", "app_state"])
        XCTAssertEqual(j.d["app"], .object(json(#"{"install_id":"ins_12345678","sdk":"ios/0.1.0"}"#)))
        XCTAssertEqual(j.d["app_state"], .object(json(#"{"foreground":false}"#)))
    }

    func testEveryVisitorFrameBuilderProducesTheDocumentedShape() {
        let frames: [String: ClientFrame] = [
            "screen": .screen(ScreenInfo(name: "home", params: ["tab": "x"])),
            "app.state": .appState(foreground: true, conversationId: "c"),
            "message.send": .send(clientId: "c1", content: "hi", conversationId: "c", attachments: ["f1"]),
            "typing": .typing(conversationId: "c", on: true),
            "read": .read(conversationId: "c", upToSeq: 9),
            "identify": .identify(userId: "u", email: "e@x.test", hash: "h", data: ["plan": "pro", "n": 2]),
            "event": .event(name: "viewed", data: ["sku": "1"]),
            "rate": .rate(conversationId: "c", score: 5, comment: "ok"),
        ]
        for (t, f) in frames {
            let j = json(encodeFrame(f))
            XCTAssertEqual(j.t, t)
            XCTAssertEqual(j.int("v"), 1)
            XCTAssertNotNil(j["d"]?.objectValue, t)
        }
        XCTAssertEqual(json(encodeFrame(frames["message.send"]!)).d, json(#"{"conversation_id":"c","client_id":"c1","content":"hi","attachments":["f1"]}"#))
        XCTAssertEqual(ClientFrame.appState(foreground: false).d, json(#"{"foreground":false,"conversation_id":null}"#))
        XCTAssertEqual(ClientFrame.appState(foreground: false).d?["conversation_id"], .null)
        XCTAssertEqual(json(encodeFrame(frames["identify"]!)).d["data"], .object(json(#"{"plan":"pro","n":2}"#)))
        XCTAssertNil(json(encodeFrame(.send(clientId: "c1", content: "hi", attachments: []))).d["attachments"])
        XCTAssertEqual(ClientFrame.event(name: "x").d, json(#"{"name":"x","data":{}}"#))
        XCTAssertNil(ClientFrame.rate(conversationId: "c", score: 4, comment: "").d?["comment"])
        XCTAssertEqual(ClientFrame.screen(ScreenInfo(name: String(repeating: "x", count: 300))).d?.str("name")?.count, 200)
        XCTAssertNil(ClientFrame.screen(ScreenInfo(name: "home", params: [:])).d?["params"])
        XCTAssertNotNil(json(encodeFrame(frames["message.send"]!)).d["attachments"]?.arrayValue)
    }

    func testJSONValueTextEscapesAndKeepsIntegers() {
        let v: JSONValue = ["a": "x\"y\n", "n": 199000, "f": 1.5, "b": true, "z": nil, "l": [1, "2"]]
        XCTAssertEqual(JSONValue.parse(v.jsonText), v)
        XCTAssertTrue(v.jsonText.contains("\"n\":199000"))
        XCTAssertEqual(JSONValue.number(150000).stringValue, "150000")
        XCTAssertEqual(JSONValue.string("12").intValue, 12)
        XCTAssertNil(JSONValue.bool(true).intValue)
        XCTAssertNil(JSONValue.string("true").boolValue)
    }
}

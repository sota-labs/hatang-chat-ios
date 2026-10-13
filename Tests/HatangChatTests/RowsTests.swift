import XCTest
@testable import HatangChat

final class RowsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z")!
    private let utc = TimeZone(identifier: "UTC")!
    private let strings = HatangChatStrings.en

    private func msg(_ id: String, _ seq: Int, _ sender: SenderType, at: Date, readAt: Date? = nil, name: String? = nil, metadata: JSONObject? = nil) -> TimelineItem {
        .message(MessageDto(id: id, conversationId: "c", seq: seq, senderType: sender, content: id, createdAt: at, senderName: name, metadata: metadata, readAt: readAt))
    }

    private func state(_ items: [TimelineItem]) -> ChatState {
        var s = ChatState()
        s.locale = .en
        s.timeline = Timeline(items: items)
        return s
    }

    func testGreetingWhenEmpty() {
        var s = state([])
        s.config = SiteConfig(greeting: ["en": "Hi there"])
        XCTAssertEqual(buildRows(s, strings: strings, now: now, timeZone: utc), [.greeting("Hi there")])
    }

    func testDaySeparatorsSeenAndLabels() {
        let y = now.addingTimeInterval(-86_400)
        var s = state([
            msg("a", 1, .visitor, at: y, readAt: now),
            msg("b", 2, .bot, at: now, name: "Hana"),
            .event(ConversationEventDto(id: "e", conversationId: "c", seq: 3, type: "handoff", createdAt: now)),
            msg("d", 4, .visitor, at: now),
        ])
        s.typingAgent = ""
        let rows = buildRows(s, strings: strings, now: now, timeZone: utc)
        guard case .day(let yLabel, _) = rows[0], case .message(let a) = rows[1], case .day(let tLabel, _) = rows[2],
              case .message(let b) = rows[3], case .message(let d) = rows[5] else { return XCTFail("\(rows)") }
        XCTAssertEqual(yLabel, "Yesterday")
        XCTAssertTrue(a.showSeen)
        XCTAssertEqual(tLabel, "Today")
        XCTAssertEqual(b.senderLabel, "Hana · \(strings.aiLabel)")
        XCTAssertEqual(rows[4], .system(id: "e", text: strings.transferredToAgent))
        XCTAssertFalse(d.showSeen)
        XCTAssertEqual(rows.last, .typing(""))
    }

    func testNoticesUseTheStringKey() {
        let rows = buildRows(state([
            .event(ConversationEventDto(id: "n", conversationId: "c", seq: 1, type: "notice", createdAt: now, data: ["key": "emailSaved"])),
            .event(ConversationEventDto(id: "x", conversationId: "c", seq: 2, type: "assigned", createdAt: now)),
        ]), strings: strings, now: now, timeZone: utc)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], .system(id: "n", text: strings.emailSaved))
    }

    func testEmailRequestOnlyWithoutAKnownEmail() {
        var s = state([msg("b", 1, .bot, at: now, metadata: ["kind": "email_request"])])
        guard case .message(let r) = buildRows(s, strings: strings, now: now, timeZone: utc)[1] else { return XCTFail() }
        XCTAssertTrue(r.askEmail)
        s.visitorEmail = "a@b.c"
        guard case .message(let r2) = buildRows(s, strings: strings, now: now, timeZone: utc)[1] else { return XCTFail() }
        XCTAssertFalse(r2.askEmail)
    }

    func testQuickRepliesOnlyOnTheNewestItem() {
        let qr: JSONObject = ["kind": "quick_replies", "options": ["Yes", "No"]]
        let rows = buildRows(state([
            msg("a", 1, .bot, at: now, metadata: qr),
            msg("b", 2, .bot, at: now, metadata: qr),
        ]), strings: strings, now: now, timeZone: utc)
        guard case .message(let a) = rows[1], case .message(let b) = rows[2] else { return XCTFail() }
        XCTAssertNil(a.card)
        guard case .quickReplies(let q) = b.card else { return XCTFail() }
        XCTAssertEqual(q.options, ["Yes", "No"])
    }

    func testCardFallbackTextIsHiddenUnderARenderedCard() {
        let order: JSONObject = ["kind": "order", "order": ["id": "o", "code": "DH1", "items": [], "total": 1]]
        let unknown: JSONObject = ["kind": "survey", "id": "x"]
        var s = state([
            msg("a", 1, .bot, at: now, metadata: order),
            msg("b", 2, .bot, at: now, metadata: unknown),
        ])
        s.timeline = Timeline(items: s.timeline.items.map {
            guard case .message(var m) = $0 else { return $0 }
            m.content = m.id == "a" ? "Đơn hàng DH1\nTổng: 1đ" : "Survey fallback"
            return .message(m)
        })
        let rows = buildRows(s, strings: strings, now: now, timeZone: utc)
        guard case .message(let a) = rows[1], case .message(let b) = rows[2] else { return XCTFail() }
        XCTAssertNotNil(a.card)
        XCTAssertEqual(a.message.content, "")
        XCTAssertNil(b.card)
        XCTAssertEqual(b.message.content, "Survey fallback")
    }

    func testPendingRowsFollowTheTimeline() {
        var s = state([])
        s.pending = [PendingMessage(clientId: "x", content: "hi", createdAt: now)]
        XCTAssertEqual(buildRows(s, strings: strings, now: now, timeZone: utc).map(\.id), ["p-x"])
    }

    func testAnnouncements() {
        let m = MessageDto(id: "m", senderType: .agent, content: "**Hi** there", createdAt: now, senderName: "Lan")
        XCTAssertEqual(announcement(for: m, strings: strings, now: now), "Lan: Hi there")
        XCTAssertNil(announcement(for: m, strings: strings, now: now.addingTimeInterval(600)))
        var mine = m
        mine.senderType = .visitor
        XCTAssertNil(announcement(for: mine, strings: strings, now: now))
        let file = MessageDto(id: "f", senderType: .agent, content: "", createdAt: now, attachments: [Attachment(id: "a", name: "bill.pdf")])
        XCTAssertEqual(announcement(for: file, strings: strings, now: now), "\(strings.team): bill.pdf")
    }
}

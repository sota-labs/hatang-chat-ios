import XCTest
@testable import HatangChatCore

final class TimelineTests: XCTestCase {
    private func msg(_ id: String, _ seq: Int, _ sender: SenderType = .agent, clientId: String? = nil, readAt: Date? = nil) -> TimelineItem {
        .message(MessageDto(
            id: id,
            conversationId: "c",
            seq: seq,
            senderType: sender,
            content: id,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(min(max(seq, 0), 59) * 60)),
            clientId: clientId,
            readAt: readAt
        ))
    }

    func testDedupesByIdSortsBySeqAndTracksLastAndOldest() {
        let t = mergeTimeline(.empty, [msg("b", 2), msg("a", 1)])
        XCTAssertEqual(t.items.map(\.id), ["a", "b"])
        XCTAssertEqual(t.lastSeq, 2)
        XCTAssertEqual(t.oldestSeq, 1)
        let t2 = mergeTimeline(t, [msg("b", 2), msg("c", 3)])
        XCTAssertEqual(t2.items.count, 3)
        XCTAssertEqual(t2.lastSeq, 3)
        XCTAssertFalse(t2.hasMore)
        XCTAssertTrue(mergeTimeline(t2, [msg("z", 0)], hasMore: true).hasMore)
    }

    func testReplacesAnItemWithTheSameId() {
        let local = msg("m1", 5, .visitor, clientId: "c1")
        let t = mergeTimeline(.empty, [local])
        var echo = local.message!
        echo.content = "server"
        XCTAssertEqual(mergeTimeline(t, [.message(echo)]).items, [.message(echo)])
    }

    func testLocalRowsSitAfterTheServerRowWithTheSameSeqAndDoNotMoveLastSeq() {
        let t = mergeTimeline(.empty, [msg("m1", 1), msg("m2", 2)])
        let t2 = mergeTimeline(t, [msg("local-1", 2, .bot)])
        XCTAssertEqual(t2.items.map(\.id), ["m1", "m2", "local-1"])
        XCTAssertEqual(t2.lastSeq, 2)
        let t3 = mergeTimeline(t2, [msg("m3", 3)])
        XCTAssertEqual(t3.items.map(\.id), ["m1", "m2", "local-1", "m3"])
        XCTAssertEqual(t3.lastSeq, 3)
    }

    func testKeepsLastSeqWhenOnlyLocalRowsAreMergedIntoAnEmptyTimeline() {
        let t = mergeTimeline(Timeline(lastSeq: 4), [msg("local-x", 0, .bot)])
        XCTAssertEqual(t.lastSeq, 4)
        XCTAssertEqual(t.oldestSeq, 0)
    }

    func testAgentReadStampsMyMessagesUpToSeq() {
        let t = mergeTimeline(.empty, [msg("a", 1, .visitor), msg("b", 2), msg("c", 3, .visitor)])
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let r = applyRead(t, side: "agent", upTo: 2, now: now)
        XCTAssertEqual(r.items[0].message?.readAt, now)
        XCTAssertNil(r.items[1].message?.readAt)
        XCTAssertNil(r.items[2].message?.readAt)
        XCTAssertEqual(applyRead(r, side: "agent", upTo: 2, now: now.addingTimeInterval(5)), r, "no change returns the same timeline")
    }

    func testVisitorReadStampsTheTeamsMessages() {
        let t = mergeTimeline(.empty, [msg("a", 1, .visitor), msg("b", 2, .bot)])
        let r = applyRead(t, side: "visitor", upTo: 5, now: Date())
        XCTAssertNil(r.items[0].message?.readAt)
        XCTAssertNotNil(r.items[1].message?.readAt)
    }

    func testReconcilePendingDropsEchoedClientIds() {
        let at = Date(timeIntervalSince1970: 0)
        let pending = [PendingMessage(clientId: "c1", content: "a", createdAt: at), PendingMessage(clientId: "c2", content: "b", createdAt: at)]
        XCTAssertEqual(reconcilePending(pending, [msg("m", 1, .visitor, clientId: "c1")]).map(\.clientId), ["c2"])
        XCTAssertEqual(reconcilePending(pending, [msg("m", 1)]), pending)
    }

    func testResumeFromAndMaxSeq() {
        XCTAssertEqual(resumeFrom(10), 0)
        XCTAssertEqual(resumeFrom(500), 350)
        XCTAssertEqual(resumeFrom(500, window: 100), 400)
        XCTAssertEqual(maxSeq([msg("a", 3), msg("local-1", 9)]), 3)
        XCTAssertEqual(maxSeq([]), 0)
    }

    func testUploadHelpers() {
        XCTAssertEqual(mimeTypeForName("IMG_1.JPG"), "image/jpeg")
        XCTAssertEqual(mimeTypeForName("voice.m4a"), "audio/mp4")
        XCTAssertNil(mimeTypeForName("setup.exe"))
        XCTAssertNil(mimeTypeForName("README"))
        XCTAssertTrue(uploadMimeTypes.contains(mimeTypeForName("a.heic")!))
        XCTAssertTrue(UploadSource(data: Data([1]), name: "a.png", mimeType: "image/png").isImage)
    }

    func testStoredSessionRoundTripsThroughTheStores() async {
        let secure = InMemoryKeyValueStore()
        let prefs = InMemoryKeyValueStore()
        let store = SessionStore(siteId: "s", secure: secure, prefs: prefs)
        let s = StoredSession(token: "t", conversationId: "c", lastSeq: 7, locale: "en", email: "a@b.test", pushToken: "p", pushProvider: "apns")
        try? await store.save(s)
        XCTAssertEqual(secure.values, ["hatang_chat.s.token": "t"])
        XCTAssertEqual(prefs.values["hatang_chat.s.last_seq"], "7")
        let loaded = await store.load()
        XCTAssertEqual(loaded, s)
        try? await store.save(s.withoutConversation())
        XCTAssertNil(prefs.values["hatang_chat.s.conversation_id"])
        XCTAssertNil(prefs.values["hatang_chat.s.last_seq"])
    }
}

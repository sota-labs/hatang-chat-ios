import XCTest
@testable import HatangChat

final class LabelsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z")!
    private let utc = TimeZone(identifier: "UTC")!

    func testFileSizes() {
        XCTAssertEqual(fileSizeLabel(12), "12 B")
        XCTAssertEqual(fileSizeLabel(850_000), "830 KB")
        XCTAssertEqual(fileSizeLabel(2_516_582), "2.4 MB")
    }

    func testErrorTexts() {
        let s = HatangChatStrings.vi
        XCTAssertEqual(errorText(nil, strings: s), s.errorGeneric)
        XCTAssertEqual(errorText(HatangError(code: "rate_limit_exceeded", message: "x"), strings: s), s.rateLimited)
        XCTAssertEqual(errorText(HatangError(code: "file_too_large", message: "x"), strings: s), s.tooLarge)
        XCTAssertEqual(errorText(HatangError(code: "timeout", message: "x"), strings: s), s.sendFailed)
        XCTAssertEqual(errorText(HatangError(code: "network_error", message: "x"), strings: s), s.errorGeneric)
        XCTAssertEqual(errorText(HatangError(code: "other", message: "Boom"), strings: s), "Boom")
    }

    func testInboxRows() {
        let s = HatangChatStrings.vi
        var c = VisitorConversationDto(id: "c1", status: .open, siteId: "s", lastMessageAt: now.addingTimeInterval(-3600), lastMessagePreview: "Xin   chào\nbạn", lastMessageSenderType: .visitor)
        var row = inboxRow(c, siteName: "Shop", strings: s, locale: .vi, now: now, timeZone: utc)
        XCTAssertEqual(row.title, "Shop")
        XCTAssertEqual(row.initial, "S")
        XCTAssertEqual(row.preview, "Bạn: Xin chào bạn")
        XCTAssertEqual(row.time, "09:00")
        XCTAssertFalse(row.finished)

        c.agent = AgentSummary(name: "lan")
        c.status = .resolved
        c.visitorUnread = 2
        c.lastMessageSenderType = .agent
        c.lastMessageAt = now.addingTimeInterval(-86_400)
        row = inboxRow(c, siteName: "Shop", strings: s, locale: .vi, now: now, timeZone: utc)
        XCTAssertEqual(row.title, "lan")
        XCTAssertEqual(row.initial, "L")
        XCTAssertEqual(row.preview, "Xin chào bạn")
        XCTAssertEqual(row.time, s.yesterday)
        XCTAssertTrue(row.finished)
        XCTAssertEqual(row.accessibilityLabel(strings: s, locale: .vi), "lan, Xin chào bạn, Hôm qua, Đã giải quyết, 2 tin nhắn mới")

        let empty = inboxRow(VisitorConversationDto(id: "c2", status: .open, siteId: "s"), siteName: "", strings: s, locale: .vi, now: now)
        XCTAssertEqual(empty.title, s.team)
        XCTAssertEqual(empty.time, "")
    }

    func testBadge() {
        XCTAssertEqual(badgeText(5), "5")
        XCTAssertEqual(badgeText(120), "99+")
    }
}

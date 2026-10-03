import XCTest
@testable import HatangChatCore

final class I18nTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testViAndEnHaveEveryKeyNonEmpty() {
        let vi = HatangChatStrings.vi.map
        let en = HatangChatStrings.en.map
        XCTAssertEqual(vi.count, 76)
        XCTAssertEqual(Set(vi.keys), Set(en.keys))
        XCTAssertEqual(Set(HatangChatStrings.keys), Set(vi.keys))
        XCTAssertEqual(HatangChatStrings.keys.count, 76)
        for (k, v) in vi { XCTAssertFalse(v.trimmingCharacters(in: .whitespaces).isEmpty, "vi.\(k) is empty") }
        for (k, v) in en { XCTAssertFalse(v.trimmingCharacters(in: .whitespaces).isEmpty, "en.\(k) is empty") }
        // The flat map covers every stored property.
        let fields = Mirror(reflecting: HatangChatStrings.vi).children.compactMap { $0.value as? String }
        XCTAssertEqual(fields.count, vi.count)
        XCTAssertEqual(Set(vi.values), Set(fields))
    }

    func testOverridesAndForLocale() {
        var custom = HatangChatStrings.en
        custom.placeholder = "Ask us"
        XCTAssertEqual(custom.placeholder, "Ask us")
        XCTAssertEqual(custom.map["placeholder"], "Ask us")
        XCTAssertEqual(custom.send, HatangChatStrings.en.send)
        XCTAssertEqual(HatangChatStrings.forLocale(.vi), .vi)
        XCTAssertEqual(HatangChatStrings.forLocale(.en), .en)
        XCTAssertEqual(HatangChatStrings.vi.placeholder, "Nhập tin nhắn…")
        XCTAssertEqual(HatangChatStrings.en.unsupportedFile, "This file type can’t be sent")
    }

    func testInterpolateAndPlurals() {
        XCTAssertEqual(interpolate("Hi {name}, {missing}", ["name": "Lan"]), "Hi Lan, {missing}")
        XCTAssertEqual(interpolate("plain"), "plain")
        XCTAssertEqual(HatangChatStrings.en.unread(1, locale: .en), "1 new message")
        XCTAssertEqual(HatangChatStrings.en.unread(2, locale: .en), "2 new messages")
        XCTAssertEqual(HatangChatStrings.vi.unread(1, locale: .vi), "1 tin nhắn mới")
        XCTAssertEqual(HatangChatStrings.en.t("messageFrom", locale: .en, params: ["name": "Lan"]), "Message from Lan")
        XCTAssertEqual(pluralCategory(.en, 1), "one")
        XCTAssertEqual(pluralCategory(.vi, 1), "other")
    }

    func testTranslateFallsBackToTheBareKeyThenTheFallbackThenTheKey() {
        XCTAssertEqual(translate(["a": "A"], locale: .en, key: "a"), "A")
        XCTAssertEqual(translate([:], locale: .en, key: "a", fallback: ["a": "FB"]), "FB")
        XCTAssertEqual(translate([:], locale: .en, key: "nope"), "nope")
        XCTAssertEqual(translate(["n": "N {count}"], locale: .en, key: "n", params: ["count": 3]), "N 3")
    }

    func testPickLocaleMatrix() {
        XCTAssertEqual(pickLocale(preferred: "en", siteDefault: "vi", deviceLanguage: "vi"), .en)
        XCTAssertEqual(pickLocale(preferred: "vi", siteDefault: "en", deviceLanguage: "en-US"), .vi)
        XCTAssertEqual(pickLocale(siteDefault: "en", deviceLanguage: "vi"), .en)
        XCTAssertEqual(pickLocale(siteDefault: "vi", deviceLanguage: "en"), .vi)
        XCTAssertEqual(pickLocale(deviceLanguage: "en-GB"), .en)
        XCTAssertEqual(pickLocale(deviceLanguage: "EN"), .en)
        XCTAssertEqual(pickLocale(deviceLanguage: "fr"), .vi)
        XCTAssertEqual(pickLocale(), .vi)
        XCTAssertEqual(pickLocale(preferred: "de", deviceLanguage: "en"), .en)
    }

    func testNumbersGroupPerLocale() {
        XCTAssertEqual(formatNumber(1234567, locale: .vi), "1.234.567")
        XCTAssertEqual(formatNumber(1234567, locale: .en), "1,234,567")
        XCTAssertEqual(formatNumber(999, locale: .en), "999")
        XCTAssertEqual(formatNumber(-1000, locale: .en), "-1,000")
        XCTAssertEqual(formatNumber(1234.5, locale: .en, decimals: 2), "1,234.50")
        XCTAssertEqual(formatNumber(1234.5, locale: .vi, decimals: 2), "1.234,50")
        XCTAssertEqual(formatNumber(1234.5, locale: .en), "1,235")
        XCTAssertEqual(formatNumber(-0.4, locale: .en), "0")
    }

    func testVndAndMoney() {
        XCTAssertEqual(vnd(150000), "150.000 ₫")
        XCTAssertEqual(vnd(150000, locale: .en), "150,000 ₫")
        XCTAssertEqual(vnd(199000.0), "199.000 ₫")
        XCTAssertEqual(money(12.5, currency: "usd", locale: .en), "12.50 USD")
        XCTAssertEqual(money(5000, currency: "VND", locale: .vi), "5.000 ₫")
    }

    func testTimeAndDayLabels() {
        XCTAssertEqual(timeOf(at(2026, 9, 27, 9, 5), timeZone: zone), "09:05")
        let now = at(2026, 9, 27, 15)
        XCTAssertEqual(dayLabel(at(2026, 9, 27, 8), locale: .en, strings: .en, now: now, timeZone: zone), "Today")
        XCTAssertEqual(dayLabel(at(2026, 9, 26, 23), locale: .vi, strings: .vi, now: now, timeZone: zone), "Hôm qua")
        XCTAssertEqual(dayLabel(at(2026, 9, 1), locale: .vi, strings: .vi, now: now, timeZone: zone), "1/9/2026")
        XCTAssertEqual(dayLabel(at(2026, 9, 1), locale: .en, strings: .en, now: now, timeZone: zone), "9/1/2026")
        XCTAssertEqual(dayOf(at(2026, 9, 27, 23, 59), timeZone: zone), CalendarDay(year: 2026, month: 9, day: 27))
    }

    func testAvailabilityLabel() {
        XCTAssertEqual(availabilityLabel(Availability(online: true), locale: .en, strings: .en, timeZone: zone), "We're online")
        XCTAssertEqual(availabilityLabel(.offline, locale: .en, strings: .en, timeZone: zone), "We're away right now")
        let monday = at(2026, 9, 28, 9)
        XCTAssertEqual(availabilityLabel(Availability(online: false, nextOpenAt: monday), locale: .en, strings: .en, timeZone: zone), "We're away right now · Back at Mon 09:00")
        XCTAssertEqual(availabilityLabel(Availability(online: false, nextOpenAt: monday), locale: .vi, strings: .vi, timeZone: zone), "Hiện chúng tôi vắng mặt · Quay lại lúc T2 09:00")
        XCTAssertEqual(weekdayShort(7, locale: .vi), "CN")
    }
}

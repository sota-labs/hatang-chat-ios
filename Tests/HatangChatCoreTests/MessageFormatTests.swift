import XCTest
@testable import HatangChatCore

final class MessageFormatTests: XCTestCase {
    func testTokenizesLinksBoldItalicCodeAndNewlines() {
        XCTAssertEqual(formatMessage("Hi **there**, see https://x.test/a?b=1. Use `npm i` _now_\nbye"), [
            .text("Hi "), .bold("there"), .text(", see "), .link(href: "https://x.test/a?b=1", label: "https://x.test/a?b=1"),
            .text(". Use "), .code("npm i"), .text(" "), .italic("now"), .br, .text("bye"),
        ])
    }

    func testNeverInterpretsHTML() {
        XCTAssertEqual(formatMessage("<b>x</b>"), [.text("<b>x</b>")])
    }

    func testHandlesCRLFAndEmptyLines() {
        XCTAssertEqual(formatMessage("a\r\n\r\nb"), [.text("a"), .br, .br, .text("b")])
    }

    func testLinkTrailingPunctuationStaysOutside() {
        XCTAssertEqual(formatMessage("see https://x.test/a, ok"), [.text("see "), .link(href: "https://x.test/a", label: "https://x.test/a"), .text(", ok")])
    }

    func testVietnameseTextKeepsItsCharacters() {
        XCTAssertEqual(formatMessage("Chào **bạn** nhé"), [.text("Chào "), .bold("bạn"), .text(" nhé")])
    }

    func testPlainTextOfFlattensAndPreviewOfTrims() {
        XCTAssertEqual(plainTextOf(formatMessage("**a** _b_ `c`\nd")), "a b c\nd")
        XCTAssertEqual(previewOf("  a\n\n b  "), "a b")
        XCTAssertEqual(previewOf(String(repeating: "x", count: 300), max: 10).count, 10)
        XCTAssertTrue(previewOf(String(repeating: "x", count: 300), max: 10).hasSuffix("…"))
    }
}

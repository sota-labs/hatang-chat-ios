import XCTest
@testable import HatangChat

final class ContrastTests: XCTestCase {
    private let white: UInt32 = 0xFFFF_FFFF
    private let black: UInt32 = 0xFF00_0000
    private let ink: UInt32 = 0xFF0B_0D12
    private let paper: UInt32 = 0xFFF6_F6F3
    private let night: UInt32 = 0xFF07_080B

    func testRatioBounds() {
        XCTAssertEqual(HatangContrast.contrastRatio(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(HatangContrast.contrastRatio(white, white), 1, accuracy: 0.0001)
        XCTAssertEqual(HatangContrast.contrastRatio(black, white), HatangContrast.contrastRatio(white, black), accuracy: 0.0001)
    }

    func testOnAccentPicksTheMoreReadableText() {
        XCTAssertEqual(HatangContrast.onAccent(for: 0xFF0E_A5E9), ink) // sky: white would be 2.8:1
        XCTAssertEqual(HatangContrast.onAccent(for: 0xFF1E_3A8A), white) // navy
        XCTAssertEqual(HatangContrast.onAccent(for: 0xFFFA_CC15), ink) // yellow
    }

    func testReadableDarkensALightAccentOnPaper() {
        let yellow: UInt32 = 0xFFFA_CC15
        let out = HatangContrast.readable(yellow, on: [paper, white])
        XCTAssertGreaterThanOrEqual(HatangContrast.contrastRatio(out, paper), 4.5)
        XCTAssertGreaterThanOrEqual(HatangContrast.contrastRatio(out, white), 4.5)
        XCTAssertLessThan(HatangContrast.luminance(out), HatangContrast.luminance(yellow))
    }

    func testReadableLightensADarkAccentOnNight() {
        let navy: UInt32 = 0xFF1E_3A8A
        let out = HatangContrast.readable(navy, on: [night])
        XCTAssertGreaterThanOrEqual(HatangContrast.contrastRatio(out, night), 4.5)
        XCTAssertGreaterThan(HatangContrast.luminance(out), HatangContrast.luminance(navy))
    }

    func testReadableColoursAreKept() {
        XCTAssertEqual(HatangContrast.readable(ink, on: [paper]), ink)
    }

    func testAlphaBlend() {
        XCTAssertEqual(HatangContrast.alphaBlend(0x0000_0000, over: white), white)
        XCTAssertEqual(HatangContrast.alphaBlend(black, over: white), black)
        XCTAssertEqual(HatangContrast.alphaBlend(0x8000_0000, over: white) & 0xFF, 0x7F)
    }

    func testParsesHexColours() {
        XCTAssertEqual(HatangContrast.parseHex("#0ea5e9"), 0xFF0E_A5E9)
        XCTAssertEqual(HatangContrast.parseHex("#fa0"), 0xFFFF_AA00)
        XCTAssertEqual(HatangContrast.parseHex("#0ea5e980"), 0x800E_A5E9)
        XCTAssertNil(HatangContrast.parseHex("blue"))
        XCTAssertNil(HatangContrast.parseHex("#12345"))
        XCTAssertNil(HatangContrast.parseHex(nil))
    }

    func testFillAccentIsLiftedOffTheDarkPage() {
        let near: UInt32 = 0xFF11_1111
        let out = HatangContrast.readable(near, on: [night], ratio: 2)
        XCTAssertGreaterThanOrEqual(HatangContrast.contrastRatio(out, night), 2)
        XCTAssertEqual(HatangContrast.readable(0xFF0E_A5E9, on: [night], ratio: 2), 0xFF0E_A5E9)
    }
}

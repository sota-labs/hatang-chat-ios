import Foundation
import HatangChatCore

/// WCAG colour maths on packed `0xAARRGGBB` values (no UIKit or SwiftUI types, so it is testable on any
/// platform). Ported from the Android and Flutter SDKs.
public enum HatangContrast {
    static let darkText: UInt32 = 0xFF0B_0D12
    static let white: UInt32 = 0xFFFF_FFFF
    static let black: UInt32 = 0xFF00_0000

    private static func channel(_ c: UInt32) -> Double {
        let s = Double(c) / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance (0 black … 1 white) of an opaque colour.
    public static func luminance(_ argb: UInt32) -> Double {
        let r = channel((argb >> 16) & 0xFF)
        let g = channel((argb >> 8) & 0xFF)
        let b = channel(argb & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// WCAG 2 contrast ratio between two opaque colours (1 to 21).
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Near-black or white, whichever reads better on `c` (a mid blue such as `#0ea5e9` gets dark text).
    public static func onAccent(for c: UInt32) -> UInt32 {
        contrastRatio(darkText, c) >= contrastRatio(white, c) ? darkText : white
    }

    /// Linear interpolation between two colours (alpha included).
    public static func lerp(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF)
            let y = Double((b >> shift) & 0xFF)
            return UInt32(min(max((x + (y - x) * t).rounded(), 0), 255))
        }
        return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    /// `top` (possibly translucent) composited over the opaque `base`.
    public static func alphaBlend(_ top: UInt32, over base: UInt32) -> UInt32 {
        let a = Double((top >> 24) & 0xFF) / 255
        func ch(_ shift: UInt32) -> UInt32 {
            let f = Double((top >> shift) & 0xFF)
            let b = Double((base >> shift) & 0xFF)
            return UInt32(min(max((f * a + b * (1 - a)).rounded(), 0), 255))
        }
        return (0xFF << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    /// `c` moved towards black or white in 5 % steps until it reaches `ratio` against every colour in
    /// `backgrounds` (opaque; blend translucent tints with `alphaBlend` first).
    public static func readable(_ c: UInt32, on backgrounds: [UInt32], ratio: Double = 4.5) -> UInt32 {
        func ok(_ x: UInt32) -> Bool { backgrounds.allSatisfy { contrastRatio(x, $0) >= ratio } }
        if ok(c) { return c }
        let avg = backgrounds.map(luminance).reduce(0, +) / Double(max(backgrounds.count, 1))
        let target = avg > 0.4 ? black : white
        for i in 1...20 {
            let x = lerp(c, target, Double(i) / 20)
            if ok(x) { return x }
        }
        return target
    }

    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` into `0xAARRGGBB`; nil when malformed.
    public static func parseHex(_ hex: String?) -> UInt32? {
        guard var h = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.allSatisfy(\.isHexDigit), let v = UInt64(h, radix: 16) else { return nil }
        switch h.count {
        case 6: return 0xFF00_0000 | UInt32(v)
        case 8: return (UInt32(v & 0xFF) << 24) | UInt32((v >> 8) & 0xFF_FFFF)
        default: return nil
        }
    }
}

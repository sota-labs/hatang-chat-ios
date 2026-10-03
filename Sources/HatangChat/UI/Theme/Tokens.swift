#if os(iOS)
import SwiftUI
import UIKit

extension Color {
    /// A colour from `0xAARRGGBB`.
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }

    /// This colour as `0xAARRGGBB` (sRGB, resolved for the current traits).
    var argb: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func ch(_ v: CGFloat) -> UInt32 { UInt32(min(max((v * 255).rounded(), 0), 255)) }
        return (ch(a) << 24) | (ch(r) << 16) | (ch(g) << 8) | ch(b)
    }
}

/// Colour palette (ported from the agent app's `theme/tokens.ts`).
public struct HatangPalette: Sendable, Hashable {
    /// Page background.
    public var bg: Color
    /// Cards, bars and the composer.
    public var surface: Color
    /// Raised surfaces (their bubbles, the text field).
    public var raised: Color
    /// Dialogs and sheets.
    public var elevated: Color
    /// Hairlines.
    public var border: Color
    /// Stronger outlines.
    public var borderStrong: Color
    /// Primary text.
    public var fg: Color
    /// Secondary text.
    public var muted: Color
    /// Tertiary text.
    public var dim: Color
    public var success: Color
    public var successSoft: Color
    public var warn: Color
    public var warnSoft: Color
    public var danger: Color
    public var dangerSoft: Color
    public var info: Color
    public var infoSoft: Color

    public init(
        bg: Color, surface: Color, raised: Color, elevated: Color, border: Color, borderStrong: Color,
        fg: Color, muted: Color, dim: Color, success: Color, successSoft: Color, warn: Color, warnSoft: Color,
        danger: Color, dangerSoft: Color, info: Color, infoSoft: Color
    ) {
        self.bg = bg
        self.surface = surface
        self.raised = raised
        self.elevated = elevated
        self.border = border
        self.borderStrong = borderStrong
        self.fg = fg
        self.muted = muted
        self.dim = dim
        self.success = success
        self.successSoft = successSoft
        self.warn = warn
        self.warnSoft = warnSoft
        self.danger = danger
        self.dangerSoft = dangerSoft
        self.info = info
        self.infoSoft = infoSoft
    }

    /// Warm off-white paper, ink-black text.
    public static let light = HatangPalette(
        bg: Color(argb: 0xFFF6_F6F3), surface: Color(argb: 0xFFFF_FFFF), raised: Color(argb: 0xFFEE_EEEA),
        elevated: Color(argb: 0xFFFF_FFFF), border: Color(argb: 0xFFE4_E4DF), borderStrong: Color(argb: 0xFFC9_C9C2),
        fg: Color(argb: 0xFF0B_0D12), muted: Color(argb: 0xFF5F_6672), dim: Color(argb: 0xFF9A_A0AA),
        success: Color(argb: 0xFF16_A34A), successSoft: Color(argb: 0x1F16_A34A),
        warn: Color(argb: 0xFFD9_7706), warnSoft: Color(argb: 0x1FD9_7706),
        danger: Color(argb: 0xFFDC_2626), dangerSoft: Color(argb: 0x1FDC_2626),
        info: Color(argb: 0xFF0E_A5E9), infoSoft: Color(argb: 0x1F0E_A5E9)
    )

    /// Near-black with cool grey surfaces stacked by elevation.
    public static let dark = HatangPalette(
        bg: Color(argb: 0xFF07_080B), surface: Color(argb: 0xFF0F_1115), raised: Color(argb: 0xFF17_1A20),
        elevated: Color(argb: 0xFF1B_1F26), border: Color(argb: 0xFF22_262E), borderStrong: Color(argb: 0xFF34_3A45),
        fg: Color(argb: 0xFFF4_F5F7), muted: Color(argb: 0xFF9A_A3B2), dim: Color(argb: 0xFF5F_6774),
        success: Color(argb: 0xFF4A_DE80), successSoft: Color(argb: 0x224A_DE80),
        warn: Color(argb: 0xFFFB_BF24), warnSoft: Color(argb: 0x22FB_BF24),
        danger: Color(argb: 0xFFF8_7171), dangerSoft: Color(argb: 0x22F8_7171),
        info: Color(argb: 0xFF38_BDF8), infoSoft: Color(argb: 0x2238_BDF8)
    )
}

/// 4-pt spacing scale.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let gutter: CGFloat = 16
}

/// Corner radii.
enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
}

/// Minimum touch target (Apple asks for 44 pt).
let minTouch: CGFloat = 44
#endif

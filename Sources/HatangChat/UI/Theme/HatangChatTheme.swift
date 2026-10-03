#if os(iOS)
import HatangChatCore
import SwiftUI

/// How the chat picks light or dark.
public enum HatangChatThemeMode: Sendable, Hashable {
    /// Follow the site's `theme` setting (`light`, `dark`, or `auto` = the device).
    case site
    /// Follow the device's appearance.
    case system
    /// Always light.
    case light
    /// Always dark.
    case dark
}

/// Colours and shapes of the chat UI. By default the SDK derives one from the site's brand colour
/// (`fromSite`); hosts may pass their own to `HatangChat.configure(theme:darkTheme:)`.
public struct HatangChatTheme: Sendable, Hashable {
    /// Dark theme.
    public var isDark: Bool
    /// Base colours.
    public var palette: HatangPalette
    /// Accent (site colour): send button, own bubbles, launcher.
    public var accent: Color
    /// Text on `accent`, chosen by contrast.
    public var onAccent: Color
    /// Bubble corner radius.
    public var bubbleRadius: CGFloat
    /// Own bubble background (default: `accent`).
    public var mineBubble: Color?
    /// Own bubble text (default: `onAccent`).
    public var onMineBubble: Color?
    /// Their bubble background (default: the raised surface).
    public var theirBubble: Color?
    /// Their bubble text (default: fg).
    public var onTheirBubble: Color?
    /// The accent as a text colour on the chat's backgrounds (quick replies, outlined buttons, links,
    /// prices): the site colour when it reads at WCAG AA (4.5:1) on the page, card and bubble backgrounds,
    /// otherwise the nearest darker (light) or lighter (dark) shade that does.
    public private(set) var accentText: Color

    public init(
        isDark: Bool,
        palette: HatangPalette,
        accent: Color,
        onAccent: Color? = nil,
        bubbleRadius: CGFloat = 20,
        mineBubble: Color? = nil,
        onMineBubble: Color? = nil,
        theirBubble: Color? = nil,
        onTheirBubble: Color? = nil
    ) {
        self.isDark = isDark
        self.palette = palette
        self.accent = accent
        self.onAccent = onAccent ?? Color(argb: HatangContrast.onAccent(for: accent.argb))
        self.bubbleRadius = bubbleRadius
        self.mineBubble = mineBubble
        self.onMineBubble = onMineBubble
        self.theirBubble = theirBubble
        self.onTheirBubble = onTheirBubble
        let backgrounds = [palette.bg.argb, palette.surface.argb, (theirBubble ?? palette.raised).argb]
        accentText = Color(argb: HatangContrast.readable(accent.argb, on: backgrounds))
    }

    /// Resolved own bubble background.
    public var mine: Color { mineBubble ?? accent }
    /// Resolved own bubble text.
    public var onMine: Color { onMineBubble ?? onAccent }
    /// Resolved their bubble background.
    public var theirs: Color { theirBubble ?? palette.raised }
    /// Resolved their bubble text.
    public var onTheirs: Color { onTheirBubble ?? palette.fg }

    /// `fg` adjusted to read at 4.5:1 on `background` (translucent backgrounds are blended over bg first).
    func readable(_ fg: Color, on background: Color) -> Color {
        let bg = HatangContrast.alphaBlend(background.argb, over: palette.bg.argb)
        return Color(argb: HatangContrast.readable(fg.argb, on: [bg]))
    }

    /// Hatang sky, light.
    public static let defaultLightAccent = Color(argb: 0xFF0E_A5E9)
    /// Hatang sky, dark.
    public static let defaultDarkAccent = Color(argb: 0xFF38_BDF8)

    /// Light theme with `accent`.
    public static func light(accent: Color = defaultLightAccent) -> HatangChatTheme {
        HatangChatTheme(isDark: false, palette: .light, accent: accent)
    }

    /// Dark theme with `accent`.
    public static func dark(accent: Color = defaultDarkAccent) -> HatangChatTheme {
        HatangChatTheme(isDark: true, palette: .dark, accent: accent)
    }

    /// Theme from the site's brand colour (`SiteConfig.color`) for light or dark.
    public static func fromSite(_ config: SiteConfig?, dark: Bool) -> HatangChatTheme {
        guard let hex = HatangContrast.parseHex(config?.color).map({ $0 | 0xFF00_0000 }) else {
            return dark ? .dark() : .light()
        }
        // A brand colour that melts into the page (near-black in dark, near-white in light) is lifted until
        // own bubbles, buttons and the launcher stand out at 2:1; text uses `accentText` (4.5:1) anyway.
        let page = dark ? 0xFF07_080B as UInt32 : 0xFFF6_F6F3
        let accent = Color(argb: HatangContrast.readable(hex, on: [page], ratio: 2))
        return dark ? .dark(accent: accent) : .light(accent: accent)
    }
}

/// Theme, locale and strings for the chat views below it.
struct ChatScope {
    var theme: HatangChatTheme
    var locale: HatangLocale
    var strings: HatangChatStrings
}

private struct ChatScopeKey: EnvironmentKey {
    static let defaultValue = ChatScope(theme: .light(), locale: .vi, strings: .vi)
}

extension EnvironmentValues {
    var chat: ChatScope {
        get { self[ChatScopeKey.self] }
        set { self[ChatScopeKey.self] = newValue }
    }
}

/// Dark or light for `site` under `mode`, given the system's `scheme`.
func isChatDark(site: SiteConfig?, mode: HatangChatThemeMode, scheme: ColorScheme) -> Bool {
    switch mode {
    case .light: return false
    case .dark: return true
    case .system: return scheme == .dark
    case .site:
        switch site?.theme {
        case .light: return false
        case .dark: return true
        default: return scheme == .dark
        }
    }
}

/// Resolves the theme (host override or brand colour) and strings, and puts them in the environment with a
/// matching colour scheme so system controls follow the chat's light or dark choice.
struct ChatThemed<Content: View>: View {
    var state: ChatState
    var overrides: HatangChat.Appearance
    @ViewBuilder var content: (ChatScope) -> Content
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let scope = overrides.scope(for: state, systemScheme: systemScheme)
        content(scope)
            .environment(\.chat, scope)
            .environment(\.colorScheme, scope.theme.isDark ? .dark : .light)
            .tint(scope.theme.accentText)
    }
}
#endif

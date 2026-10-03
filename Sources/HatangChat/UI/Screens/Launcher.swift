#if os(iOS)
import HatangChatCore
import SwiftUI

/// A floating chat button with an unread badge. Place it over your content, e.g.
/// `.overlay(alignment: .bottomTrailing) { HatangChatLauncher().padding() }`. Tapping calls `action`, or
/// `HatangChat.present()`.
///
/// It uses the site's brand colour and the icon or image and label set for the launcher in the dashboard
/// (a label makes it a capsule such as "Hỗ trợ"), and hides itself while the team is away when the site
/// asks for that (`hide_when_offline`). Renders nothing before `HatangChat.configure`.
public struct HatangChatLauncher: View {
    private let model: HatangChatModel
    private let showBadge: Bool
    private let action: (() -> Void)?
    private let systemImage: String?
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 56

    /// - Parameters:
    ///   - model: model override (default: `HatangChat.model`).
    ///   - showBadge: show the unread count.
    ///   - systemImage: an SF Symbol replacing the site's icon and label.
    ///   - action: tap action (default: `HatangChat.present()`).
    public init(model: HatangChatModel? = nil, showBadge: Bool = true, systemImage: String? = nil, action: (() -> Void)? = nil) {
        self.model = model ?? HatangChat.model
        self.showBadge = showBadge
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        let state = model.state
        let config = state.config
        if model.engine != nil, !(config?.hideWhenOffline == true && !state.online) {
            let theme = model.appearance.theme(for: config, systemScheme: scheme)
            let strings = model.appearance.strings(for: state.locale)
            let launcher = config?.launcher ?? LauncherConfig()
            let label = systemImage == nil ? launcher.labelFor(state.locale).flatMap { $0.isEmpty ? nil : $0 } : nil
            let unread = state.unread
            let name = label ?? strings.open
            Button {
                if let action { action() } else { HatangChat.present() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    glyph(launcher)
                    if let label {
                        Text(label).font(.headline).lineLimit(1)
                    }
                }
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, label == nil ? 0 : Spacing.lg)
                .frame(minWidth: size, minHeight: size)
                .background(theme.accent, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if showBadge && unread > 0 {
                    Text(badgeText(unread))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(theme.palette.danger, in: Capsule())
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(unread > 0 ? "\(name), \(strings.unread(unread, locale: state.locale))" : name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if let action { action() } else { HatangChat.present() } }
        }
    }

    @ViewBuilder
    private func glyph(_ launcher: LauncherConfig) -> some View {
        if let systemImage {
            Image(systemName: systemImage).font(.title2)
        } else if let url = launcher.imageUrl.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Image(systemName: "bubble.left.fill").font(.title2)
                }
            }
            .frame(width: size * 0.57, height: size * 0.57)
            .clipShape(Circle())
        } else {
            Image(systemName: Self.symbol(launcher.icon)).font(.title2)
        }
    }

    static func symbol(_ icon: LauncherIcon) -> String {
        switch icon {
        case .chat: return "bubble.left.fill"
        case .support: return "headphones"
        case .help: return "questionmark.circle"
        case .message: return "bubble.left"
        }
    }
}
#endif

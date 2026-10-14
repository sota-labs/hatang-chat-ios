#if os(iOS)
import HatangChatCore
import SwiftUI

/// Title of the chat: the business logo or the online agents' faces, site name, the site's subtitle,
/// availability dot and line.
struct ChatTitle: View {
    let title: String
    let availability: Availability?
    let avatars: [AgentAvatar]
    var header: HeaderConfig?
    /// Site name, for the logo's letter when there is no logo image.
    var siteName = ""
    @Environment(\.chat) private var chat
    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 26

    var body: some View {
        let t = chat.theme
        let subtitle = header?.subtitleFor(chat.locale)
        HStack(spacing: Spacing.sm) {
            if header?.profile == .business {
                HeaderCircle(
                    initial: initial(siteName.isEmpty ? title : siteName),
                    imageUrl: header?.logoUrl,
                    size: avatarSize * 1.2
                )
                .accessibilityHidden(true)
            } else if !avatars.isEmpty {
                HStack(spacing: -avatarSize * 0.4) {
                    ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { _, a in
                        HeaderCircle(initial: initial(a.name), imageUrl: a.avatarUrl, size: avatarSize)
                    }
                }
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: subtitle == nil ? 1 : -1) {
                Text(title)
                    .font(subtitle == nil ? .headline : .footnote.weight(.semibold))
                    .foregroundStyle(t.palette.fg)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(t.palette.muted)
                        .lineLimit(1)
                }
                if let availability {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(availability.online ? t.palette.success : t.palette.dim)
                            .frame(width: 8, height: 8)
                        Text(availabilityLabel(availability, locale: chat.locale, strings: chat.strings))
                            .font(subtitle == nil ? .caption : .caption2)
                            .foregroundStyle(t.palette.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
        // Three lines only just fit the bar, so they stop growing past xLarge.
        .dynamicTypeSize(subtitle == nil ? DynamicTypeSize.xSmall ... .accessibility5 : DynamicTypeSize.xSmall ... .xLarge)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

/// One circle in the title: an https image over the accent-coloured initial (shown while loading or when
/// the image fails).
private struct HeaderCircle: View {
    let initial: String
    let imageUrl: String?
    let size: CGFloat
    @Environment(\.chat) private var chat

    var body: some View {
        let t = chat.theme
        ZStack {
            Circle().fill(t.accent)
            Text(initial)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(t.onAccent)
            if let url = imageUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(t.palette.surface, lineWidth: 2))
    }
}

/// Other ways to reach the business (Zalo, Messenger, phone, email) as a row of pills under the title.
struct ContactButtonsRow: View {
    let buttons: [ContactButton]
    @Environment(\.chat) private var chat

    var body: some View {
        let t = chat.theme
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in
                    ContactPill(button: b)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.sm)
        }
        .background(t.palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(t.palette.border).frame(height: 1) }
    }
}

/// One contact button. The link opens through `openURL`, so Zalo and Messenger links open their apps
/// (universal links) when installed, `tel:` the dialer and `mailto:` the mail app.
struct ContactPill: View {
    let button: ContactButton
    @Environment(\.chat) private var chat
    @Environment(\.openURL) private var openURL

    var body: some View {
        let t = chat.theme
        if let url = URL(string: button.url) {
            Button { openURL(url) } label: {
                Label(label, systemImage: symbol)
                    .labelStyle(PillLabelStyle())
                    .fixedSize()
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(t.palette.fg)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(t.palette.raised, in: Capsule())
                    .overlay(Capsule().strokeBorder(t.palette.border))
            }
            .buttonStyle(.plain)
        }
    }

    private var label: String {
        switch button.kind {
        case .phone: return chat.strings.call
        case .email: return chat.strings.emailUs
        default: return button.label.isEmpty ? button.kind.code.capitalized : button.label
        }
    }

    private var symbol: String {
        switch button.kind {
        case .phone: return "phone.fill"
        case .email: return "envelope.fill"
        case .messenger: return "message.fill"
        default: return "bubble.left.fill"
        }
    }
}

/// Icon and title close together, the icon in the accent colour.
private struct PillLabelStyle: LabelStyle {
    @Environment(\.chat) private var chat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon.foregroundStyle(chat.theme.accentText).imageScale(.small)
            configuration.title.lineLimit(1)
        }
    }
}

/// The chat inside a navigation stack: the title bar (site name, availability, close) over the
/// conversation. Switches to `conversationId` whenever `openSerial` changes.
struct ConversationScreen: View {
    let model: HatangChatModel
    var conversationId: String?
    var openSerial = 0
    var title: String?
    var onClose: (() -> Void)?

    var body: some View {
        ChatThemed(state: model.state, overrides: model.appearance) { scope in
            let state = model.state
            ConversationBody(model: model)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ChatTitle(
                            title: title ?? state.config?.name ?? "",
                            availability: state.config == nil ? nil : state.availability,
                            avatars: state.config?.agentAvatars ?? [],
                            header: state.config?.header,
                            siteName: state.config?.name ?? ""
                        )
                    }
                    if let onClose {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onClose) {
                                Image(systemName: "xmark").font(.body.weight(.semibold))
                            }
                            .foregroundStyle(scope.theme.palette.fg)
                            .accessibilityLabel(scope.strings.close)
                        }
                    }
                }
                .toolbarBackground(scope.theme.palette.surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(scope.theme.isDark ? .dark : .light, for: .navigationBar)
        }
        .task(id: OpenKey(id: conversationId, serial: openSerial)) {
            guard let id = conversationId, let engine = model.engine else { return }
            await engine.openConversation(id)
        }
    }

    private struct OpenKey: Hashable {
        let id: String?
        let serial: Int
    }
}

/// The full chat screen: a navigation bar with the site name and availability, the conversation and the
/// composer. `HatangChat.present()` shows it modally; hosts with their own navigation can place it
/// directly (set `embedInNavigationStack: false` to push it onto your stack).
public struct HatangChatView: View {
    private let model: HatangChatModel
    private let conversationId: String?
    private let title: String?
    private let onClose: (() -> Void)?
    private let embed: Bool

    /// - Parameters:
    ///   - conversationId: conversation to show (default: the active one).
    ///   - model: model override (default: `HatangChat.model`).
    ///   - title: title override (default: the site name).
    ///   - embedInNavigationStack: wrap in a `NavigationStack` (off when pushing onto yours).
    ///   - onClose: shows a close button that calls it (nil hides it).
    public init(
        conversationId: String? = nil,
        model: HatangChatModel? = nil,
        title: String? = nil,
        embedInNavigationStack: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.model = model ?? HatangChat.model
        self.conversationId = conversationId
        self.title = title
        self.onClose = onClose
        embed = embedInNavigationStack
    }

    public var body: some View {
        if embed {
            NavigationStack { screen }
        } else {
            screen
        }
    }

    private var screen: some View {
        ConversationScreen(model: model, conversationId: conversationId, title: title, onClose: onClose)
    }
}
#endif

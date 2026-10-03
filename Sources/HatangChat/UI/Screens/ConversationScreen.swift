#if os(iOS)
import HatangChatCore
import SwiftUI

/// Title of the chat: team initials, site name, availability dot and line.
struct ChatTitle: View {
    let title: String
    let availability: Availability?
    let avatars: [AgentAvatar]
    @Environment(\.chat) private var chat
    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 26

    var body: some View {
        let t = chat.theme
        HStack(spacing: Spacing.sm) {
            if !avatars.isEmpty {
                HStack(spacing: -avatarSize * 0.4) {
                    ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { _, a in
                        Text(a.name.first.map { String($0).uppercased() } ?? "?")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(t.onAccent)
                            .frame(width: avatarSize, height: avatarSize)
                            .background(t.accent, in: Circle())
                            .overlay(Circle().strokeBorder(t.palette.surface, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(t.palette.fg)
                    .lineLimit(1)
                if let availability {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(availability.online ? t.palette.success : t.palette.dim)
                            .frame(width: 8, height: 8)
                        Text(availabilityLabel(availability, locale: chat.locale, strings: chat.strings))
                            .font(.caption)
                            .foregroundStyle(t.palette.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                            avatars: state.config?.agentAvatars ?? []
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

#if os(iOS)
import HatangChatCore
import SwiftUI

/// The visitor's conversations, newest activity first (pull to refresh, more pages on scroll).
struct InboxScreen: View {
    let model: HatangChatModel
    let onOpen: (VisitorConversationDto) -> Void
    let onNew: () -> Void
    var onClose: (() -> Void)?
    @State private var rows: [VisitorConversationDto] = []
    @State private var hasMore = false
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        ChatThemed(state: model.state, overrides: model.appearance) { scope in
            let t = scope.theme
            VStack(spacing: 0) {
                content(scope)
                    .frame(maxHeight: .infinity)
                Button(action: onNew) {
                    Label(scope.strings.newConversation, systemImage: "square.and.pencil")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(ChatButtonStyle(fullWidth: true))
                .padding(Spacing.gutter)
                .background(t.palette.bg)
            }
            .background(t.palette.bg)
            .navigationTitle(scope.strings.inboxTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) { Image(systemName: "xmark").font(.body.weight(.semibold)) }
                            .foregroundStyle(t.palette.fg)
                            .accessibilityLabel(scope.strings.close)
                    }
                }
            }
            .toolbarBackground(t.palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(t.isDark ? .dark : .light, for: .navigationBar)
        }
        // Reload when the engine becomes ready (cold start), for a new visitor, and when shown again.
        .task(id: ReloadKey(phase: model.phase, visitor: model.visitor?.id)) { await load(reset: true) }
        .onAppear { Task { await load(reset: true) } }
    }

    private struct ReloadKey: Hashable {
        let phase: ChatPhase
        let visitor: String?
    }

    @ViewBuilder
    private func content(_ scope: ChatScope) -> some View {
        let t = scope.theme
        if rows.isEmpty && loading {
            ProgressView().tint(t.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(t.palette.muted)
                        .accessibilityHidden(true)
                    Text(failed ? scope.strings.inboxError : scope.strings.noConversations)
                        .font(.subheadline)
                        .foregroundStyle(t.palette.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
                .padding(.horizontal, Spacing.gutter)
            }
            .refreshable { await load(reset: true) }
        } else {
            List {
                ForEach(rows, id: \.id) { c in
                    InboxRow(model: inboxRow(c, siteName: model.config?.name ?? "", strings: scope.strings, locale: scope.locale)) {
                        onOpen(c)
                    }
                    .listRowBackground(t.palette.bg)
                    .listRowSeparatorTint(t.palette.border)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.gutter, bottom: 0, trailing: Spacing.gutter))
                }
                .listSectionSeparator(.hidden, edges: .top)
                if hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(t.palette.bg)
                        .listRowSeparator(.hidden)
                        .onAppear { Task { await load(reset: false) } }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load(reset: true) }
        }
    }

    private func load(reset: Bool) async {
        guard !loading, let engine = model.engine else { return }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let page = try await engine.listConversations(after: reset || rows.isEmpty ? nil : rows.last?.id)
            if reset { rows = [] }
            let known = Set(rows.map(\.id))
            rows += page.conversations.filter { !known.contains($0.id) }
            hasMore = page.hasMore
        } catch {
            if !(error is CancellationError) { failed = true }
        }
    }
}

/// One conversation in the inbox.
struct InboxRow: View {
    let model: InboxRowModel
    let onTap: () -> Void
    @Environment(\.chat) private var chat
    @ScaledMetric(relativeTo: .body) private var avatar: CGFloat = 44

    var body: some View {
        let t = chat.theme
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle().fill(t.palette.raised).overlay(Circle().fill(t.accent.opacity(0.15)))
                    Text(model.initial).font(.headline).foregroundStyle(t.accentText)
                    if let url = model.avatarURL.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                        }
                        .clipShape(Circle())
                    }
                }
                .frame(width: avatar, height: avatar)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.title)
                            .font(.body.weight(model.unread > 0 ? .bold : .semibold))
                            .foregroundStyle(t.palette.fg)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        Text(model.time).font(.caption).foregroundStyle(t.palette.muted)
                    }
                    HStack(spacing: Spacing.sm) {
                        Text(model.preview)
                            .font(.subheadline)
                            .foregroundStyle(model.unread > 0 ? t.palette.fg : t.palette.muted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if model.finished {
                            Text(chat.strings.resolved).font(.caption).foregroundStyle(t.palette.muted)
                        } else if model.unread > 0 {
                            Text(badgeText(model.unread))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(t.onAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(t.accent, in: Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(strings: chat.strings, locale: chat.locale))
        .accessibilityAddTraits(.isButton)
    }
}

/// The visitor's conversation list: who answered, the last message, when, unread count and status.
/// Tapping one opens it (pushed on the navigation stack; back returns to the list); "New message" opens
/// the current conversation, or an empty one.
public struct HatangChatInbox: View {
    private let model: HatangChatModel
    private let onClose: (() -> Void)?
    private let onOpenConversation: ((VisitorConversationDto) -> Void)?

    /// - Parameters:
    ///   - model: model override (default: `HatangChat.model`).
    ///   - onOpenConversation: called after the engine switched to the tapped conversation, to show it your
    ///     own way (default: push `HatangChatView`).
    ///   - onClose: shows a close button (nil hides it).
    public init(
        model: HatangChatModel? = nil,
        onOpenConversation: ((VisitorConversationDto) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.model = model ?? HatangChat.model
        self.onOpenConversation = onOpenConversation
        self.onClose = onClose
    }

    public var body: some View {
        ChatRootView(navigator: ChatNavigator(start: .inbox), model: model, onClose: onClose, onOpenConversation: onOpenConversation)
    }
}
#endif

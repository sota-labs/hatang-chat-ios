#if os(iOS)
import HatangChatCore
import SwiftUI

/// The rows of `buildRows`, newest at the bottom. Earlier history loads when the top comes into view (the
/// reading position is kept), new rows are followed when the reader is at the bottom, and new messages from
/// the team are announced to VoiceOver.
struct MessageList: View {
    let state: ChatState
    let onRetry: (String) -> Void
    let onLoadEarlier: () -> Void
    let onSubmitEmail: (String) async -> Void
    let onAttachmentExpired: (MessageDto) -> Void
    let actions: CardActions
    @Environment(\.chat) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atBottom = true
    @State private var keepTop: String?
    @State private var announced: String?

    var body: some View {
        let rows = buildRows(state, strings: chat.strings)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if state.timeline.hasMore {
                        loadEarlier.id("load-earlier")
                    }
                    ForEach(rows) { row in
                        rowView(row).id(row.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: rows.last?.id) { _, _ in
                let mineLast: Bool
                if case .pending = rows.last { mineLast = true } else { mineLast = false }
                guard atBottom || mineLast else { return }
                if reduceMotion {
                    proxy.scrollTo("bottom", anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: state.loadingEarlier) { was, now in
                // Keep the row that was at the top in place once the earlier page is in.
                if was && !now, let id = keepTop {
                    keepTop = nil
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) }
                }
            }
            .onChange(of: state.conversation?.id) { _, _ in
                announced = latestIncoming?.id
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .onAppear { announced = latestIncoming?.id }
        .onChange(of: latestIncoming?.id) { _, id in
            guard let id, id != announced, let m = latestIncoming else { return }
            announced = id
            if let text = announcement(for: m, strings: chat.strings) {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }

    private var latestIncoming: MessageDto? {
        for case .message(let m) in state.timeline.items.reversed() where !m.isMine && !m.id.hasPrefix("local-") { return m }
        return nil
    }

    private var loadEarlier: some View {
        Group {
            if state.loadingEarlier {
                ProgressView().frame(minHeight: minTouch)
            } else {
                Button(chat.strings.loadEarlier, action: load)
                    .font(.subheadline)
                    .foregroundStyle(chat.theme.accentText)
                    .frame(minHeight: minTouch)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .onAppear(perform: load)
    }

    private func load() {
        guard state.timeline.hasMore, !state.loadingEarlier else { return }
        keepTop = state.timeline.items.first.map { "m-\($0.id)" }
        if case .event = state.timeline.items.first { keepTop = nil }
        onLoadEarlier()
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow) -> some View {
        let s = chat.strings
        switch row {
        case .day(let label, _):
            DaySeparator(label: label)
        case .greeting(let text, let sender):
            MessageBubble(message: MessageDto(id: "greeting", senderType: .bot, content: text, createdAt: Date()), mine: false, senderLabel: sender)
        case .system(_, let text):
            SystemLine(text: text)
        case .message(let r):
            MessageBubble(
                message: r.message,
                mine: r.mine,
                senderLabel: r.senderLabel,
                showSeen: r.showSeen,
                onAttachmentExpired: { onAttachmentExpired(r.message) },
                hideEmptyBubble: r.card != nil,
                footerFullWidth: r.card != nil
            ) {
                if r.askEmail {
                    EmailRequestForm(onSubmit: onSubmitEmail)
                } else if let card = r.card {
                    MessageCardView(card: card, actions: actions, rated: state.rated)
                }
            }
        case .pending(let p):
            MessageBubble(
                message: MessageDto(id: "pending-\(p.clientId)", senderType: .visitor, content: p.content, createdAt: p.createdAt),
                mine: true,
                dimmed: p.failed || p.upload == nil,
                upload: p.upload,
                onTap: p.failed ? { onRetry(p.clientId) } : nil,
                tapLabel: s.retry
            ) {
                if p.failed {
                    Text("\(s.failed) · \(s.retry)")
                        .font(.caption)
                        .foregroundStyle(chat.theme.readable(chat.theme.palette.danger, on: chat.theme.palette.bg))
                        .padding(.trailing, Spacing.xs)
                }
            }
        case .typing(let name):
            TypingIndicator(name: name)
        }
    }
}
#endif

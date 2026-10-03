#if os(iOS)
import HatangChatCore
import SwiftUI

/// One message bubble with the optional sender label and "Seen" marker. Pictures show as thumbnails that
/// open the viewer, other files as rows that open the file. VoiceOver reads the text, then who sent it and
/// when.
struct MessageBubble<Footer: View>: View {
    let message: MessageDto
    let mine: Bool
    var senderLabel: String?
    var showSeen = false
    var dimmed = false
    var upload: PendingUpload?
    var onTap: (() -> Void)?
    var tapLabel: String?
    var onAttachmentExpired: (() -> Void)?
    var hideEmptyBubble = false
    var footerFullWidth = false
    @ViewBuilder var footer: () -> Footer
    @Environment(\.chat) private var chat

    var body: some View {
        let t = chat.theme
        let empty = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.attachments.isEmpty && upload == nil
        let who = mine ? chat.strings.you : (senderLabel ?? chat.strings.team)
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if !(hideEmptyBubble && empty) {
                row {
                    bubble(fg: mine ? t.onMine : t.onTheirs)
                        .background(mine ? t.mine : t.theirs, in: shape)
                        .clipShape(shape)
                        .opacity(dimmed ? 0.6 : 1)
                        .contentShape(shape)
                        .onTapGesture { onTap?() }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue("\(who), \(timeOf(message.createdAt))")
                        .modifier(TapAction(label: tapLabel, action: onTap))
                }
            }
            if footerFullWidth {
                footer()
            } else {
                row { footer() }
            }
            if senderLabel != nil || showSeen {
                Text(showSeen ? chat.strings.read : (senderLabel ?? ""))
                    .font(.caption)
                    .foregroundStyle(t.palette.muted)
                    .padding(.horizontal, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.vertical, 2)
    }

    private var shape: UnevenRoundedRectangle {
        let r = chat.theme.bubbleRadius
        return mine
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: Radius.xs, topTrailingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: Radius.xs, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    /// Keeps bubbles to about 80 % of the width.
    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 56) }
            content()
            if !mine { Spacer(minLength: 56) }
        }
    }

    private func bubble(fg: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !message.content.isEmpty {
                Text(formattedText(message.content))
                    .font(.body)
                    .foregroundStyle(fg)
                    .tint(mine ? fg : chat.theme.accentText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(message.attachments, id: \.id) { a in
                AttachmentView(attachment: a, foreground: fg, onExpired: onAttachmentExpired)
            }
            if let upload {
                PendingAttachmentView(upload: upload, foreground: fg)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
    }
}

extension MessageBubble where Footer == EmptyView {
    init(message: MessageDto, mine: Bool, senderLabel: String? = nil) {
        self.init(message: message, mine: mine, senderLabel: senderLabel, footer: { EmptyView() })
    }
}

/// Exposes a tap as a named VoiceOver action ("Retry").
private struct TapAction: ViewModifier {
    let label: String?
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text(label ?? "")) { action() }
        } else {
            content
        }
    }
}
#endif

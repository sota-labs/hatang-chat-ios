#if os(iOS)
import HatangChatCore
import SwiftUI

/// SF Symbol for a file's MIME type.
func symbolFor(_ type: String) -> String {
    if type.hasPrefix("image/") { return "photo" }
    if type.hasPrefix("video/") { return "film" }
    if type.hasPrefix("audio/") { return "waveform" }
    if type == "application/pdf" { return "doc.richtext" }
    if type.contains("sheet") || type.contains("excel") || type == "text/csv" { return "tablecells" }
    if type.contains("zip") { return "doc.zipper" }
    return "doc"
}

/// A centred day label between messages ("Today", "Yesterday", a date).
struct DaySeparator: View {
    let label: String
    @Environment(\.chat) private var chat

    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(chat.theme.palette.muted)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(chat.theme.palette.raised, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A system line (notice, handoff, rating thanks).
struct SystemLine: View {
    let text: String
    @Environment(\.chat) private var chat

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(chat.theme.palette.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
    }
}

/// "Chat by hatang.dev" under the composer, as the web widget shows it. Plain text on purpose: a link
/// would send the customer to a browser in the middle of a support conversation. Relabel it with the
/// `poweredBy` string override.
struct BrandingLine: View {
    @Environment(\.chat) private var chat

    var body: some View {
        Text(chat.strings.poweredBy)
            .font(.caption2)
            .foregroundStyle(chat.theme.palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Spacing.xs)
    }
}

/// Shown instead of the composer on a closed conversation, with "New message".
struct ClosedBar: View {
    let onNew: () -> Void
    @Environment(\.chat) private var chat

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(chat.theme.palette.border)
            HStack {
                Text(chat.strings.conversationClosed)
                    .font(.subheadline)
                    .foregroundStyle(chat.theme.palette.muted)
                Spacer()
                Button(chat.strings.newConversation, action: onNew)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chat.theme.accentText)
                    .frame(minHeight: minTouch)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.xs)
        }
    }
}

/// A one-line tinted banner with an optional action; tapping it dismisses when `onDismiss` is set.
struct Banner: View {
    let text: String
    let background: Color
    let foreground: Color
    var actionLabel: String?
    var onAction: (() -> Void)?
    var onDismiss: (() -> Void)?
    @Environment(\.chat) private var chat

    var body: some View {
        let fg = chat.theme.readable(foreground, on: background)
        HStack(spacing: Spacing.sm) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.xs)
            if let actionLabel, let onAction {
                Button(actionLabel, action: onAction)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(fg)
                    .frame(minHeight: minTouch)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(minHeight: 36)
        .background(chat.theme.palette.bg)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss?() }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(chat.strings.dismiss)) { onDismiss?() }
    }
}

/// Connection, outdated and error banners derived from `state`.
struct ConnectionBanners: View {
    let state: ChatState
    let onReconnect: () -> Void
    let onDismissError: () -> Void
    let localError: String?
    let onDismissLocal: () -> Void
    @Environment(\.chat) private var chat

    var body: some View {
        let s = chat.strings
        let p = chat.theme.palette
        VStack(spacing: 0) {
            if state.phase == .outdated {
                Banner(text: s.updateApp, background: p.warnSoft, foreground: p.warn)
            } else if state.phase == .failed {
                Banner(text: errorText(state.transientError, strings: s), background: p.dangerSoft, foreground: p.danger, actionLabel: s.retry, onAction: onReconnect)
            } else if state.connection == .connecting {
                Banner(text: s.connecting, background: p.infoSoft, foreground: p.info)
            } else if state.connection == .disconnected && state.phase == .ready {
                Banner(text: s.offlineBanner, background: p.warnSoft, foreground: p.warn, actionLabel: s.reconnect, onAction: onReconnect)
            }
            if let err = state.transientError, state.phase != .failed {
                Banner(text: errorText(err, strings: s), background: p.dangerSoft, foreground: p.danger, onDismiss: onDismissError)
            }
            if let localError {
                Banner(text: localError, background: p.dangerSoft, foreground: p.danger, onDismiss: onDismissLocal)
            }
        }
    }
}

/// `formatMessage` tokens as an `AttributedString`: links, bold, italic and inline code.
func formattedText(_ text: String) -> AttributedString {
    var out = AttributedString()
    for tok in formatMessage(text) {
        switch tok {
        case .text(let v):
            out += AttributedString(v)
        case .br:
            out += AttributedString("\n")
        case .bold(let v):
            var a = AttributedString(v)
            a.inlinePresentationIntent = .stronglyEmphasized
            out += a
        case .italic(let v):
            var a = AttributedString(v)
            a.inlinePresentationIntent = .emphasized
            out += a
        case .code(let v):
            var a = AttributedString(v)
            a.inlinePresentationIntent = .code
            out += a
        case .link(let href, let label):
            var a = AttributedString(label)
            a.link = URL(string: href)
            a.underlineStyle = .single
            out += a
        }
    }
    return out
}

/// Three pulsing dots in a "their" bubble; static when Reduce Motion is on.
struct TypingIndicator: View {
    let name: String
    @Environment(\.chat) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 7

    var body: some View {
        let label = name.isEmpty ? chat.strings.typing : "\(name) \(chat.strings.typing)"
        Group {
            if reduceMotion {
                dots { _ in 0.6 }
            } else {
                TimelineView(.animation) { ctx in
                    let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    dots { i in
                        let x = ((phase - Double(i) * 0.2).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                        return 0.3 + 0.7 * wave(x)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .background(chat.theme.theirs, in: RoundedRectangle(cornerRadius: chat.theme.bubbleRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func dots(_ opacity: @escaping (Int) -> Double) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(chat.theme.palette.muted).frame(width: dot, height: dot).opacity(opacity(i))
            }
        }
    }

    /// A short bump around x ∈ [0, 0.4], flat elsewhere.
    private func wave(_ x: Double) -> Double {
        guard x >= 0, x <= 0.4 else { return 0 }
        let p = x / 0.4
        return p < 0.5 ? p * 2 : (1 - p) * 2
    }
}

/// Wraps its children onto new lines (quick replies).
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// Primary (filled) or secondary (outlined) button used by cards and forms.
struct ChatButtonStyle: ButtonStyle {
    var primary: Bool = true
    var fullWidth: Bool = false
    @Environment(\.chat) private var chat
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let t = chat.theme
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minTouch)
            .foregroundStyle(primary ? t.onAccent : t.accentText)
            .background {
                let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                if primary {
                    shape.fill(t.accent)
                } else {
                    shape.strokeBorder(t.palette.border, lineWidth: 1)
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .contentShape(Rectangle())
    }
}

/// Rounded text field look used by the forms.
struct ChatFieldStyle: ViewModifier {
    @Environment(\.chat) private var chat

    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(chat.theme.palette.fg)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .frame(minHeight: minTouch)
            .background(chat.theme.palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(chat.theme.palette.borderStrong, lineWidth: 1))
    }
}

extension View {
    func chatField() -> some View { modifier(ChatFieldStyle()) }
}
#endif

#if os(iOS)
import HatangChatCore
import SwiftUI
import UIKit

/// What a card can ask the chat to do.
struct CardActions {
    /// "Buy" on a product (host hook, else prefill the composer).
    var onBuy: (ProductCardItem) -> Void
    /// "Pay" (host hook, else the web checkout).
    var onPay: (PaymentCard) -> Void
    /// A quick reply: send its label.
    var onReply: (String) -> Void
    /// A rating was sent.
    var onRate: (Int, String?) -> Void
    /// Show the VietQR code and the web checkout.
    var externalCheckout = true
    /// The host handles "Pay" itself.
    var hasPayHandler = false
}

/// The card for `card`, placed under the message that carries it.
struct MessageCardView: View {
    let card: MessageCard
    let actions: CardActions
    let rated: Int?

    var body: some View {
        Group {
            switch card {
            case .product(let c): ProductCardView(card: c, onBuy: actions.onBuy)
            case .order(let c): OrderCardView(card: c)
            case .payment(let c): PaymentCardView(card: c, onPay: actions.onPay, externalCheckout: actions.externalCheckout, hasPayHandler: actions.hasPayHandler)
            case .quickReplies(let c): QuickRepliesView(options: c.options, onReply: actions.onReply)
            case .csat(let c): CsatCardView(rated: rated ?? (c.answered ? 0 : nil), onRate: actions.onRate)
            }
        }
        .padding(.top, Spacing.xs)
    }
}

/// The rounded surface every card sits on, under the agent's bubble.
struct CardFrame<Content: View>: View {
    var width: CGFloat? = 280
    var padding: CGFloat = Spacing.md
    @ViewBuilder var content: () -> Content
    @Environment(\.chat) private var chat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        content()
            .padding(padding)
            .frame(width: width, alignment: .leading)
            .background(chat.theme.palette.surface, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(chat.theme.palette.border, lineWidth: 1))
    }
}

/// A label/value line (order lines, totals, transfer note); wraps under large text instead of overflowing.
struct CardLine<Trailing: View>: View {
    let label: String
    let value: String
    var strong = false
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.chat) private var chat

    var body: some View {
        let t = chat.theme
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                labelText
                Spacer(minLength: Spacing.sm)
                valueRow
            }
            VStack(alignment: .leading, spacing: 2) {
                labelText
                valueRow
            }
        }
        .padding(.vertical, 2)
        .foregroundStyle(strong ? t.palette.fg : t.palette.muted)
    }

    private var labelText: some View {
        Text(label).font(strong ? .subheadline : .footnote)
    }

    private var valueRow: some View {
        HStack(spacing: 0) {
            Text(value)
                .font((strong ? Font.subheadline : .footnote).weight(.semibold).monospacedDigit())
                .foregroundStyle(chat.theme.palette.fg)
            trailing()
        }
    }
}

extension CardLine where Trailing == EmptyView {
    init(label: String, value: String, strong: Bool = false) {
        self.init(label: label, value: value, strong: strong, trailing: { EmptyView() })
    }
}

/// A small coloured pill ("Paid", "Expired").
struct StatusChip: View {
    let label: String
    let color: Color
    let background: Color
    @Environment(\.chat) private var chat

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(chat.theme.readable(color, on: background))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
    }
}

/// Up to five products side by side: image, name, price (old price struck through), "View" and "Buy".
struct ProductCardView: View {
    let card: ProductCard
    let onBuy: (ProductCardItem) -> Void

    var body: some View {
        let items = Array(card.products.prefix(5))
        if items.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(items, id: \.self) { ProductTile(item: $0, onBuy: onBuy) }
                }
            }
        } else if let item = items.first {
            ProductTile(item: item, onBuy: onBuy)
        }
    }
}

private struct ProductTile: View {
    let item: ProductCardItem
    let onBuy: (ProductCardItem) -> Void
    @Environment(\.chat) private var chat
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 200

    var body: some View {
        let t = chat.theme
        let price = money(item.price, currency: item.currency, locale: chat.locale)
        let compare = item.compareAtPrice.flatMap { $0 > item.price ? money($0, currency: item.currency, locale: chat.locale) : nil }
        let w = min(width, 280)
        CardFrame(width: w, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let image = item.imageUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: image) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { t.palette.raised }
                    }
                    .frame(width: w, height: w * 3 / 4)
                    .clipped()
                    .accessibilityLabel(item.name)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(t.palette.fg)
                        .lineLimit(2)
                    FlowLayout {
                        Text(price).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(t.accentText)
                        if let compare {
                            Text(compare).font(.caption).strikethrough().foregroundStyle(t.palette.muted)
                        }
                    }
                    HStack(spacing: Spacing.sm) {
                        if let url = item.url.flatMap(URL.init(string:)) {
                            Button(chat.strings.view) { openURL(url) }
                                .buttonStyle(ChatButtonStyle(primary: false, fullWidth: true))
                        }
                        Button(chat.strings.buy) { onBuy(item) }
                            .buttonStyle(ChatButtonStyle(fullWidth: true))
                    }
                    .padding(.top, Spacing.xs)
                }
                .padding(Spacing.md)
            }
        }
    }
}

/// An order summary: code, paid tag, lines, discount, shipping and total.
struct OrderCardView: View {
    let card: OrderCard
    @Environment(\.chat) private var chat

    var body: some View {
        let t = chat.theme
        let s = chat.strings
        func m(_ v: Double) -> String { money(v, currency: card.currency, locale: chat.locale) }
        return CardFrame {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(s.order) \(card.code)").font(.subheadline.weight(.semibold)).foregroundStyle(t.palette.fg)
                    Spacer()
                    if card.isPaid { StatusChip(label: s.paid, color: t.palette.success, background: t.palette.successSoft) }
                }
                .padding(.bottom, Spacing.sm)
                ForEach(Array(card.items.enumerated()), id: \.offset) { _, i in
                    let variant = (i.variant ?? "").isEmpty ? "" : " (\(i.variant!))"
                    CardLine(label: "\(i.name)\(variant) × \(i.quantity)", value: m(i.price * Double(i.quantity)))
                }
                if card.discount > 0 { CardLine(label: s.discount, value: "-\(m(card.discount))") }
                if card.shipping > 0 { CardLine(label: s.shipping, value: m(card.shipping)) }
                Divider().overlay(t.palette.border).padding(.vertical, Spacing.sm)
                CardLine(label: s.total, value: m(card.total), strong: true)
            }
        }
    }
}

/// A payment request: amount, VietQR code, the copyable transfer note and "Pay". Paid and expired requests
/// say so and hide the QR, the transfer note and the button. Without external checkout there is no QR and no web checkout.
struct PaymentCardView: View {
    let card: PaymentCard
    let onPay: (PaymentCard) -> Void
    let externalCheckout: Bool
    let hasPayHandler: Bool
    @Environment(\.chat) private var chat
    @State private var copied = false

    var body: some View {
        let t = chat.theme
        let s = chat.strings
        // Rows mark the card paid once the timeline has its `order_paid` (see `PaidPayments`).
        let paid = PaidPayments.statusIsPaid(card.status)
        let expired = !paid && (card.status == "expired" || (card.expiresAt.map { $0 < Date() } ?? false))
        let canCheckout = externalCheckout && card.checkoutUrl.hasPrefix("http")
        let canPay = !paid && !expired && (canCheckout || hasPayHandler)
        let showQr = !paid && !expired && externalCheckout && (!card.qrImageUrl.isEmpty || card.qrPayload != nil)
        let amount = money(card.amount, currency: card.currency, locale: chat.locale)
        CardFrame {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text([s.pay, card.orderCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(t.palette.fg)
                    Spacer()
                    if paid { StatusChip(label: s.paid, color: t.palette.success, background: t.palette.successSoft) }
                    if expired { StatusChip(label: s.expired, color: t.palette.muted, background: t.palette.raised) }
                }
                Text(amount).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(t.palette.fg)
                if showQr {
                    PaymentQRCodeView(card: card, label: "VietQR \(amount)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.sm)
                    Text(s.scanToPay)
                        .font(.caption)
                        .foregroundStyle(t.palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if externalCheckout && !paid {
                    CardLine(label: s.transferNote, value: card.code) {
                        if !paid {
                            Button {
                                UIPasteboard.general.string = card.code
                                copied = true
                                AccessibilityNotification.Announcement(s.copied).post()
                            } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundStyle(copied ? t.palette.success : t.palette.muted)
                                    .frame(width: minTouch, height: minTouch)
                            }
                            .accessibilityLabel(copied ? s.copied : s.copy)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
                if canPay {
                    Button { onPay(card) } label: {
                        if hasPayHandler {
                            Text(s.pay)
                        } else {
                            Label(s.pay, systemImage: "arrow.up.forward.square")
                        }
                    }
                    .buttonStyle(ChatButtonStyle(fullWidth: true))
                    .padding(.top, Spacing.xs)
                } else if !paid && !expired {
                    Text(s.payWithTeam).font(.caption).foregroundStyle(t.palette.muted).padding(.top, Spacing.xs)
                }
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// The VietQR code of a payment card, drawn natively from the EMVCo payload (the gateway serves the image as
/// SVG, which iOS cannot decode). Shows a spinner while it looks the payload up and a retry button if that
/// fails, never an endless spinner.
struct PaymentQRCodeView: View {
    let card: PaymentCard
    let label: String
    @Environment(\.chat) private var chat
    @State private var phase: Phase = .loading
    @State private var attempt = 0

    enum Phase: Equatable {
        case loading
        case ready(UIImage)
        case failed
    }

    var body: some View {
        let t = chat.theme
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .ready(let image):
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit().accessibilityLabel(label)
            case .failed:
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "qrcode")
                        .font(.largeTitle)
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .accessibilityHidden(true)
                    Button(chat.strings.retry) { attempt += 1 }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(chat.theme.readable(t.accent, on: .white))
                        .frame(minHeight: minTouch)
                }
            }
        }
        .frame(width: 184, height: 184)
        .padding(Spacing.sm)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.sm))
        .task(id: TaskKey(card: card.id, payload: card.qrPayload, url: card.qrImageUrl, attempt: attempt)) { await load() }
    }

    private struct TaskKey: Hashable {
        let card: String
        let payload: String?
        let url: String
        let attempt: Int
    }

    private func load() async {
        if case .ready = phase { return }
        phase = .loading
        do {
            let source = try await PaymentQR.resolve(card)
            let image: UIImage? = switch source {
            case .payload(let p): PaymentQR.image(payload: p).map { UIImage(cgImage: $0) }
            case .image(let data): UIImage(data: data)
            }
            guard !Task.isCancelled else { return }
            phase = image.map { .ready($0) } ?? .failed
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }
}

/// Buttons under a bot message; tapping one sends its label as the reply.
struct QuickRepliesView: View {
    let options: [String]
    let onReply: (String) -> Void
    @Environment(\.chat) private var chat

    var body: some View {
        let t = chat.theme
        FlowLayout {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Button { onReply(o) } label: {
                    Text(o)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(t.accentText)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: minTouch)
                        .overlay(Capsule().strokeBorder(t.accent.opacity(0.5), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The rating prompt after a conversation is resolved: 1–5 stars, an optional comment, send.
struct CsatCardView: View {
    let rated: Int?
    let onRate: (Int, String?) -> Void
    @Environment(\.chat) private var chat
    @State private var score = 0
    @State private var comment = ""

    var body: some View {
        let t = chat.theme
        let s = chat.strings
        if let rated {
            CardFrame(width: nil) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { n in
                        Image(systemName: n <= rated ? "star.fill" : "star")
                            .font(.subheadline)
                            .foregroundStyle(n <= rated ? t.palette.warn : t.palette.dim)
                    }
                    Text(s.rateThanks).font(.caption).foregroundStyle(t.palette.muted).padding(.leading, Spacing.sm)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(rated)/5. \(s.rateThanks)")
            }
        } else {
            CardFrame {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(s.ratePrompt).font(.subheadline.weight(.semibold)).foregroundStyle(t.palette.fg)
                    HStack(spacing: 0) {
                        ForEach(1...5, id: \.self) { n in
                            Button { score = n } label: {
                                Image(systemName: n <= score ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(n <= score ? t.palette.warn : t.palette.muted)
                                    .frame(minWidth: minTouch, minHeight: minTouch)
                            }
                            .accessibilityLabel("\(n)/5")
                            .accessibilityAddTraits(n == score ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if score > 0 {
                        TextField(s.rateComment, text: $comment, axis: .vertical)
                            .lineLimit(1...3)
                            .onChange(of: comment) { _, v in if v.count > 1000 { comment = String(v.prefix(1000)) } }
                            .chatField()
                        Button(s.rateSend) {
                            let c = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                            onRate(score, c.isEmpty ? nil : c)
                        }
                        .buttonStyle(ChatButtonStyle(fullWidth: true))
                    }
                }
            }
        }
    }
}
#endif

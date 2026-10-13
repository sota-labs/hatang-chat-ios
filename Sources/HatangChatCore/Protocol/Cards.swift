import Foundation

/// A rich card carried in `MessageDto.metadata` (`kind` + payload). Every channel degrades to the message
/// text; the SDK renders the card under the bubble.
public enum MessageCard: Sendable, Hashable {
    case product(ProductCard)
    case order(OrderCard)
    case payment(PaymentCard)
    case quickReplies(QuickRepliesCard)
    case csat(CsatCard)

    /// The `kind` discriminator.
    public var kind: String {
        switch self {
        case .product: return "product"
        case .order: return "order"
        case .payment: return "payment"
        case .quickReplies: return "quick_replies"
        case .csat: return "csat"
        }
    }
}

/// One product in a `ProductCard`.
public struct ProductCardItem: Sendable, Hashable {
    public var id: String
    public var name: String
    public var price: Double
    /// Currency code.
    public var currency: String
    /// Strike-through price.
    public var compareAtPrice: Double?
    public var imageUrl: String?
    /// Product page URL.
    public var url: String?
    public var sku: String?
    /// App Store product id, when the shop sells this through in-app purchase.
    public var appStoreProductId: String?
    /// Google Play product id, when the shop sells this through in-app purchase.
    public var googlePlayProductId: String?

    /// Sold through in-app purchase on at least one store.
    public var hasStoreProduct: Bool { appStoreProductId != nil || googlePlayProductId != nil }

    /// Parses the wire shape.
    public init(json j: JSONObject) {
        let store = j.obj("store_product_ids") ?? [:]
        id = j.strOr("id")
        name = j.strOr("name")
        price = j.num("price") ?? 0
        compareAtPrice = j.num("compare_at_price")
        currency = j.strOr("currency", "VND")
        imageUrl = j.str("image_url")
        url = j.str("url")
        sku = j.str("sku")
        appStoreProductId = store.str("app_store")
        googlePlayProductId = store.str("google_play")
    }
}

/// A product carousel.
public struct ProductCard: Sendable, Hashable {
    /// Products (the widget shows at most five).
    public var products: [ProductCardItem]
    /// The line the sender wrote above the products.
    public var intro: String? = nil
}

/// One line of an order.
public struct OrderCardItem: Sendable, Hashable {
    public var name: String
    public var quantity: Int
    /// Unit price.
    public var price: Double
    /// Variant label.
    public var variant: String?

    public init(json j: JSONObject) {
        name = j.strOr("name")
        quantity = j.intOr("quantity", 1)
        price = j.num("price") ?? 0
        variant = j.str("variant")
    }
}

/// An order summary.
public struct OrderCard: Sendable, Hashable {
    public var id: String
    public var code: String
    public var status: String
    public var items: [OrderCardItem]
    public var subtotal: Double
    public var discount: Double
    public var shipping: Double
    public var total: Double
    public var currency: String
    /// `paid` or `unpaid`.
    public var paymentStatus: String

    /// The order was paid.
    public var isPaid: Bool { paymentStatus == "paid" }

    /// Parses the `order` object.
    public init(json o: JSONObject) {
        id = o.strOr("id")
        code = o.strOr("code")
        status = o.strOr("status")
        items = o.objList("items").map(OrderCardItem.init(json:))
        subtotal = o.num("subtotal") ?? 0
        discount = o.num("discount") ?? 0
        shipping = o.num("shipping") ?? 0
        total = o.num("total") ?? 0
        currency = o.strOr("currency", "VND")
        paymentStatus = o.strOr("payment_status", "unpaid")
    }
}

/// A payment request (VietQR).
public struct PaymentCard: Sendable, Hashable {
    public var id: String
    public var amount: Double
    public var currency: String
    public var checkoutUrl: String
    public var qrImageUrl: String
    /// The raw VietQR (EMVCo) string, when the card carries it (`qr_payload` or `qr.payload`). The SDK draws
    /// the code from it natively; otherwise it looks the payload up from the checkout (see `PaymentQR`).
    public var qrPayload: String?
    /// Transfer note.
    public var code: String
    public var status: String
    public var orderId: String?
    public var orderCode: String?
    public var expiresAt: Date?

    /// Parses the `payment` object.
    public init(json p: JSONObject) {
        id = p.strOr("id")
        orderId = p.str("order_id")
        orderCode = p.str("order_code")
        amount = p.num("amount") ?? 0
        currency = p.strOr("currency", "VND")
        checkoutUrl = p.strOr("checkout_url")
        qrImageUrl = p.strOr("qr_image_url")
        qrPayload = (p.str("qr_payload") ?? p.obj("qr")?.str("payload")).flatMap { $0.isEmpty ? nil : $0 }
        code = p.strOr("code")
        expiresAt = p.date("expires_at")
        status = p.strOr("status")
    }
}

/// Buttons under a bot message; tapping one sends its label.
public struct QuickRepliesCard: Sendable, Hashable {
    public var options: [String]
}

/// A rating prompt after resolve.
public struct CsatCard: Sendable, Hashable {
    /// Labels (channels use them as quick replies).
    public var options: [String]
    /// Already answered.
    public var answered: Bool
}

/// Port of `cardOf` from `@hatang/chat-protocol`: the card in `metadata`, if any. Unknown kinds are nil.
public func cardOf(_ metadata: JSONObject?) -> MessageCard? {
    guard let m = metadata else { return nil }
    switch m.str("kind") {
    case "product":
        guard m["products"]?.arrayValue != nil else { return nil }
        return .product(ProductCard(products: m.objList("products").map(ProductCardItem.init(json:)), intro: m.str("intro")))
    case "order":
        return m.obj("order").map { .order(OrderCard(json: $0)) }
    case "payment":
        return m.obj("payment").map { .payment(PaymentCard(json: $0)) }
    case "quick_replies":
        guard m["options"]?.arrayValue != nil else { return nil }
        return .quickReplies(QuickRepliesCard(options: m.stringList("options")))
    case "csat":
        guard m["options"]?.arrayValue != nil else { return nil }
        return .csat(CsatCard(options: m.stringList("options"), answered: m.boolOr("answered")))
    default:
        return nil
    }
}

/// The text to show in the bubble of a message that carries `card`.
///
/// The gateway always stores a plain-text rendering of product, order and payment cards in `content`
/// (optionally after an intro line) so e-mail, previews, push and other channels make sense. The SDK draws
/// those cards itself, so the plain-text copy is dropped and only the intro is kept: from `metadata.intro`
/// (which the gateway sends with every card kind), or, for messages older than that, the lines before
/// the order / payment summary. Quick replies and ratings keep the text (it is the question), and without
/// a card the content is shown as is.
public func cardBubbleText(_ content: String, card: MessageCard?, intro metadataIntro: String? = nil) -> String {
    let lines = content.components(separatedBy: "\n")
    func intro(before index: Int?) -> String {
        guard let index else { return "" }
        return lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    switch card {
    case nil, .quickReplies?, .csat?:
        return content
    case _ where metadataIntro != nil:
        return metadataIntro!.trimmingCharacters(in: .whitespacesAndNewlines)
    case .product(let c)?:
        return c.intro?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    case .order(let c)?:
        let head = "Đơn hàng \(c.code)"
        return intro(before: lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == head })
    case .payment?:
        let start = lines.indices.first { i in
            lines[i].hasPrefix("Thanh toán") && i + 1 < lines.count && lines[i + 1].hasPrefix("Quét mã VietQR")
        }
        return intro(before: start)
    }
}

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
        return .product(ProductCard(products: m.objList("products").map(ProductCardItem.init(json:))))
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

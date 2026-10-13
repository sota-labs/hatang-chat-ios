import XCTest
@testable import HatangChatCore

final class CardsTests: XCTestCase {
    func testProductWithInAppPurchaseIds() {
        guard case .product(let c) = cardOf(json("""
        {"kind":"product","products":[
          {"id":"p1","name":"Pro","price":99000,"currency":"VND","store_product_ids":{"app_store":"com.shop.pro","google_play":null}},
          {"id":"p2","name":"Tea","price":1,"currency":"VND"}]}
        """)) else { return XCTFail() }
        XCTAssertEqual(MessageCard.product(c).kind, "product")
        XCTAssertEqual(c.products.first?.appStoreProductId, "com.shop.pro")
        XCTAssertNil(c.products.first?.googlePlayProductId)
        XCTAssertTrue(c.products.first!.hasStoreProduct)
        XCTAssertFalse(c.products.last!.hasStoreProduct)
        XCTAssertEqual(c.products.first?.price, 99000)
    }

    func testProduct() {
        guard case .product(let c) = cardOf(json(#"{"kind":"product","products":[{"id":"p1","name":"Áo","price":100000,"currency":"VND","compare_at_price":120000}]}"#)) else { return XCTFail() }
        XCTAssertEqual(c.products.first?.compareAtPrice, 120000)
    }

    func testOrder() {
        guard case .order(let c) = cardOf(json("""
        {"kind":"order","order":{"id":"o","code":"A1","status":"paid","items":[{"name":"Áo","quantity":2,"price":"50000","variant":"L"}],
          "subtotal":100000,"discount":0,"shipping":30000,"total":130000,"currency":"VND","payment_status":"paid"}}
        """)) else { return XCTFail() }
        XCTAssertTrue(c.isPaid)
        XCTAssertEqual(c.items.first?.quantity, 2)
        XCTAssertEqual(c.items.first?.price, 50000)
        XCTAssertEqual(c.total, 130000)
    }

    func testPayment() {
        guard case .payment(let c) = cardOf(json("""
        {"kind":"payment","payment":{"id":"p","order_id":null,"order_code":null,"amount":5,"currency":"VND",
          "checkout_url":"https://x","qr_image_url":"https://q","code":"NOTE","expires_at":"2026-10-01T00:00:00.000Z","status":"pending"}}
        """)) else { return XCTFail() }
        XCTAssertEqual(c.code, "NOTE")
        XCTAssertNil(c.orderId)
        XCTAssertEqual(c.expiresAt, ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
    }

    func testQuickRepliesAndCsat() {
        guard case .quickReplies(let q) = cardOf(json(#"{"kind":"quick_replies","options":["a","b"]}"#)) else { return XCTFail() }
        XCTAssertEqual(q.options, ["a", "b"])
        guard case .csat(let c) = cardOf(json(#"{"kind":"csat","options":["1"],"answered":true}"#)) else { return XCTFail() }
        XCTAssertTrue(c.answered)
        guard case .csat(let c2) = cardOf(json(#"{"kind":"csat","options":[]}"#)) else { return XCTFail() }
        XCTAssertFalse(c2.answered)
    }

    func testRejectsMalformedAndUnknownKinds() {
        XCTAssertNil(cardOf(nil))
        XCTAssertNil(cardOf(json(#"{"kind":"product"}"#)))
        XCTAssertNil(cardOf(json(#"{"kind":"order","order":"x"}"#)))
        XCTAssertNil(cardOf(json(#"{"kind":"payment"}"#)))
        XCTAssertNil(cardOf(json(#"{"kind":"quick_replies","options":"a"}"#)))
        XCTAssertNil(cardOf(json(#"{"kind":"email_request"}"#)))
        XCTAssertNil(cardOf(json(#"{"kind":"lead","source":"form"}"#)))
        XCTAssertNil(cardOf(json("{}")))
    }

    // MARK: - PaidPayments

    private func payment(_ status: String = "pending", id: String = "pay1", order: String? = "ord1") -> PaymentCard {
        var j: JSONObject = ["id": .string(id), "status": .string(status), "amount": 5, "code": "NOTE"]
        if let order { j["order_id"] = .string(order) }
        return PaymentCard(json: j)
    }

    private func paidMessage(_ order: String) -> TimelineItem {
        .message(MessageDto(id: "m-\(order)", senderType: .system, content: "paid", createdAt: Date(), metadata: ["kind": "order_paid", "order_id": .string(order), "code": "DH1", "value": 5]))
    }

    private func paidEvent(_ data: JSONObject) -> TimelineItem {
        .event(ConversationEventDto(id: "e", seq: 9, type: "order_paid", createdAt: Date(), data: data))
    }

    func testPaymentPaidByItsOwnStatus() {
        XCTAssertTrue(PaidPayments.none.isPaid(payment("paid")))
        XCTAssertTrue(PaidPayments.none.isPaid(payment("succeeded")))
        XCTAssertFalse(PaidPayments.none.isPaid(payment("pending")))
    }

    func testPaymentPaidByAnOrderPaidMessage() {
        let paid = PaidPayments([paidMessage("ord1")])
        XCTAssertTrue(paid.isPaid(payment()))
        XCTAssertFalse(paid.isPaid(payment(order: "ord2")))
        XCTAssertFalse(paid.isPaid(payment(order: nil)))
    }

    func testPaymentPaidByAnOrderPaidEvent() {
        XCTAssertTrue(PaidPayments([paidEvent(["payment_id": "pay1"])]).isPaid(payment(order: nil)))
        XCTAssertTrue(PaidPayments([paidEvent(["order_id": "ord1", "payment_id": "other"])]).isPaid(payment()))
        XCTAssertFalse(PaidPayments([paidEvent(["order_id": "ord2", "payment_id": "pay2"])]).isPaid(payment()))
        // Other kinds and event types do not count; empty ids never match.
        let noise = PaidPayments([
            .event(ConversationEventDto(id: "x", type: "order_created", data: ["order_id": "ord1", "payment_id": "pay1"])),
            .message(MessageDto(id: "y", senderType: .system, content: "", createdAt: Date(), metadata: ["kind": "order", "order_id": "ord1"])),
            paidEvent(["order_id": "", "payment_id": ""]),
        ])
        XCTAssertFalse(noise.isPaid(payment()))
        XCTAssertFalse(noise.isPaid(payment(id: "", order: "")))
    }

    func testResolveMarksOnlyPaidPaymentCards() {
        let paid = PaidPayments([paidMessage("ord1")])
        guard case .payment(let p)? = paid.resolve(.payment(payment())) else { return XCTFail() }
        XCTAssertEqual(p.status, "paid")
        XCTAssertEqual(paid.resolve(.payment(payment(order: "ord2"))), .payment(payment(order: "ord2")))
        XCTAssertEqual(paid.resolve(.payment(payment("succeeded"))), .payment(payment("succeeded")))
        XCTAssertEqual(paid.resolve(.quickReplies(QuickRepliesCard(options: ["a"]))), .quickReplies(QuickRepliesCard(options: ["a"])))
        XCTAssertNil(paid.resolve(nil))
    }
}

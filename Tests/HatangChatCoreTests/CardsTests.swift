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
}

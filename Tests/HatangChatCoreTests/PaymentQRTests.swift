import XCTest
@testable import HatangChatCore

final class PaymentQRTests: XCTestCase {
    private let payload = "00020101021238570010A000000727012700069704220113VQRQ00000000102080QRIBFTTA53037045405500005802VN62100806NOTE016304ABCD"

    private func card(_ extra: String = "", url: String = "https://api.test/pay/pay_1/qr.svg") -> PaymentCard {
        guard case .payment(let c) = cardOf(json("""
        {"kind":"payment","payment":{"id":"pay_1","amount":50000,"currency":"VND","checkout_url":"https://pay.test/pay_1",
          "qr_image_url":"\(url)","code":"NOTE01","status":"pending"\(extra)}}
        """)) else { fatalError("no card") }
        return c
    }

    func testPayloadParsedFromEitherShape() {
        XCTAssertNil(card().qrPayload)
        XCTAssertEqual(card(#","qr_payload":"abc""#).qrPayload, "abc")
        XCTAssertEqual(card(#","qr":{"payload":"xyz","image_url":"u"}"#).qrPayload, "xyz")
        XCTAssertNil(card(#","qr_payload":"""#).qrPayload)
    }

    func testCheckoutURLFromGatewaySvg() {
        XCTAssertEqual(PaymentQR.checkoutURL(forImageURL: URL(string: "https://api.test/pay/pay_1/qr.svg?logo=0")!)?.absoluteString, "https://api.test/pay/pay_1")
        XCTAssertEqual(PaymentQR.checkoutURL(forImageURL: URL(string: "http://localhost:3001/v1/pay/p/qr.png")!)?.absoluteString, "http://localhost:3001/v1/pay/p")
        XCTAssertNil(PaymentQR.checkoutURL(forImageURL: URL(string: "https://cdn.test/qr/abc.png")!))
        XCTAssertNil(PaymentQR.checkoutURL(forImageURL: URL(string: "https://cdn.test/x/y/qr.svg")!))
    }

    func testRasterSniffing() {
        XCTAssertTrue(PaymentQR.isRaster(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])))
        XCTAssertTrue(PaymentQR.isRaster(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        XCTAssertFalse(PaymentQR.isRaster(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)))
        XCTAssertFalse(PaymentQR.isRaster(Data()))
    }

    func testCardPayloadNeedsNoRequest() async throws {
        let server = StubServer()
        let source = try await PaymentQR.resolve(card(#","qr_payload":"\#(payload)""#), session: server.session)
        XCTAssertEqual(source, .payload(payload))
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testSvgUrlResolvesPayloadFromCheckout() async throws {
        let server = StubServer()
        server.enqueue(.json(#"{"object":"checkout","id":"pay_1","qr":{"payload":"\#(payload)","image_url":"https://api.test/pay/pay_1/qr.svg"}}"#))
        let source = try await PaymentQR.resolve(card(), session: server.session)
        XCTAssertEqual(source, .payload(payload))
        XCTAssertEqual(server.requests.map(\.url.absoluteString), ["https://api.test/pay/pay_1"])
    }

    func testCheckoutErrorFails() async {
        let server = StubServer()
        server.enqueue(.json(#"{"name":"product_disabled"}"#, status: 403))
        do {
            _ = try await PaymentQR.resolve(card(), session: server.session)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PaymentQRError, .http(403))
        }
    }

    func testRasterImageUrlIsUsed() async throws {
        let server = StubServer()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])
        server.enqueue(.response(status: 200, body: png, headers: ["content-type": "image/png"]))
        let source = try await PaymentQR.resolve(card(url: "https://cdn.test/qr/abc.png"), session: server.session)
        XCTAssertEqual(source, .image(png))
    }

    func testSvgAtOtherUrlFailsInsteadOfSpinning() async {
        let server = StubServer()
        server.enqueue(.response(status: 200, body: Data("<svg/>".utf8), headers: ["content-type": "image/svg+xml"]))
        do {
            _ = try await PaymentQR.resolve(card(url: "https://cdn.test/qr/abc.svg"), session: server.session)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PaymentQRError, .undecodable)
        }
    }

    func testNoSource() async {
        do {
            _ = try await PaymentQR.resolve(card(url: ""), session: StubServer().session)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PaymentQRError, .noSource)
        }
    }

    #if canImport(CoreImage)
    func testDrawsQrFromPayload() throws {
        let img = try XCTUnwrap(PaymentQR.image(payload: payload))
        XCTAssertEqual(img.width, img.height)
        XCTAssertGreaterThanOrEqual(img.width, 21 + 8) // version 1 plus the quiet zone, at least
        XCTAssertNil(PaymentQR.image(payload: ""))
    }
    #endif

    // MARK: bubble text

    func testCardBubbleTextKeepsOnlyTheIntro() {
        let pay = card(#","order_code":"DH1""#)
        let payText = "Bạn thanh toán giúp mình theo mã bên dưới nhé:\nThanh toán đơn DH1 50.000đ\nQuét mã VietQR hoặc mở link: https://pay.test/pay_1\nNội dung chuyển khoản: NOTE01"
        XCTAssertEqual(cardBubbleText(payText, card: .payment(pay)), "Bạn thanh toán giúp mình theo mã bên dưới nhé:")
        XCTAssertEqual(cardBubbleText(String(payText.split(separator: "\n", maxSplits: 1)[1]), card: .payment(pay)), "")

        guard case .order(let order)? = cardOf(json(#"{"kind":"order","order":{"id":"o","code":"DH1","items":[],"total":1}}"#)) else { return XCTFail() }
        XCTAssertEqual(cardBubbleText("Đơn hàng DH1\n• Áo × 1 — 1đ\nTổng: 1đ", card: .order(order)), "")
        XCTAssertEqual(cardBubbleText("Đơn của bạn đây\nĐơn hàng DH1\nTổng: 1đ", card: .order(order)), "Đơn của bạn đây")

        guard case .product(let withIntro)? = cardOf(json(#"{"kind":"product","intro":"Mẫu mới nè","products":[]}"#)),
              case .product(let bare)? = cardOf(json(#"{"kind":"product","products":[]}"#)) else { return XCTFail() }
        XCTAssertEqual(cardBubbleText("Mẫu mới nè\n• Áo — 1đ", card: .product(withIntro)), "Mẫu mới nè")
        XCTAssertEqual(cardBubbleText("• Áo — 1đ", card: .product(bare)), "")

        XCTAssertEqual(cardBubbleText("Rate us?", card: .csat(CsatCard(options: ["1"], answered: false))), "Rate us?")
        XCTAssertEqual(cardBubbleText("Pick one", card: .quickReplies(QuickRepliesCard(options: ["a"]))), "Pick one")
        XCTAssertEqual(cardBubbleText("Plain", card: nil), "Plain")
        // The gateway's own intro wins over parsing, whatever the summary wording.
        XCTAssertEqual(cardBubbleText("Gửi bạn\nOrder DH1\nTotal: 1đ", card: .order(order), intro: " Gửi bạn "), "Gửi bạn")
        XCTAssertEqual(cardBubbleText("Rate us?", card: .csat(CsatCard(options: ["1"], answered: false)), intro: "x"), "Rate us?")
    }
}

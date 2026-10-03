import XCTest
@testable import HatangChatCore

final class WidgetAPITests: XCTestCase {
    private let server = StubServer()
    private let app = AppContext(installId: "ins_12345678", sdk: "ios/0.1.0", os: "ios")
    private let ua = "hatang-chat-ios/0.1.0 (ios/18.1; protocol/1)"

    private func api(_ base: String = "https://gw.test", timeout: Duration = .seconds(20)) -> WidgetAPI {
        WidgetAPI(baseURL: base, siteId: "site_1", appKey: "hak_test", userAgent: ua, session: server.session, timeout: timeout)
    }

    private var last: RecordedRequest { server.requests.last! }

    private func errorOf(_ reply: StubReply, file: StaticString = #filePath, line: UInt = #line) async -> HatangError? {
        server.enqueue(reply)
        do {
            _ = try await api().bootstrap(app: app)
            XCTFail("expected a HatangError", file: file, line: line)
            return nil
        } catch {
            return error as? HatangError
        }
    }

    func testBootstrapCarriesTheAppKeyAndUserAgentNoTokenHeader() async throws {
        server.enqueue(.json(bootstrapFixture()))
        let boot = try await api().bootstrap(app: app, token: "tok_old", locale: "vi")
        let req = last
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/widget/v1/sites/site_1/bootstrap")
        XCTAssertEqual(req.header("x-hatang-app-key"), "hak_test")
        XCTAssertEqual(req.header("user-agent"), ua)
        XCTAssertNil(req.header("x-visitor-token"))
        XCTAssertTrue(req.header("content-type")?.hasPrefix("application/json") ?? false)
        let body = req.json
        XCTAssertEqual(body.str("token"), "tok_old")
        XCTAssertEqual(body["locale"], "vi")
        XCTAssertEqual(body["app"], .object(json(#"{"install_id":"ins_12345678","sdk":"ios/0.1.0","os":"ios"}"#)))
        XCTAssertNil(body["screen"])
        XCTAssertEqual(boot.visitorToken, "tok_1")
        XCTAssertEqual(boot.conversation?.id, "conv_1")
        XCTAssertEqual(boot.timeline.count, 3)
        XCTAssertTrue(boot.wsUrl.hasPrefix("ws://"))
    }

    func testTokenCallsCarryTheVisitorTokenAndTheAppKey() async throws {
        server.enqueue(.json(#"{"conversations":[{"id":"c1","status":"open","seq":3,"agent":{"name":"Lan"}},"junk"],"has_more":true}"#))
        let page = try await api().listConversations(token: "tok_1", limit: 20)
        let req = last
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.header("x-visitor-token"), "tok_1")
        XCTAssertEqual(req.header("x-hatang-app-key"), "hak_test")
        XCTAssertNil(req.header("content-type"))
        XCTAssertEqual(req.query, ["status": "all", "limit": "20"])
        XCTAssertEqual(page.conversations.map { $0.agent?.name }, ["Lan"])
        XCTAssertTrue(page.hasMore)
    }

    func testABaseURLWithAPathPrefixKeepsIt() async throws {
        server.enqueue(.json(bootstrapFixture()))
        _ = try await api("https://gw.test/chat/").bootstrap(app: app)
        XCTAssertEqual(last.path, "/chat/widget/v1/sites/site_1/bootstrap")
    }

    func testBeforeSeqPagesBackAndDropsAfterSeq() async throws {
        server.enqueue(.json(#"{"items":[\#(frame("message").d.text)],"has_more":true}"#))
        let page = try await api().messages(token: "t", conversationId: "conv_1", afterSeq: 3, beforeSeq: 40, limit: 50)
        XCTAssertEqual(last.path, "/widget/v1/sites/site_1/conversations/conv_1/messages")
        XCTAssertEqual(last.query, ["before_seq": "40", "limit": "50"])
        XCTAssertNotNil(page.items.first?.message)
        XCTAssertTrue(page.hasMore)
    }

    func testAfterSeqSyncsForward() async throws {
        server.enqueue(.json(#"{"items":[],"has_more":false}"#))
        _ = try await api().messages(token: "t", conversationId: "c", afterSeq: 7, limit: 1)
        XCTAssertEqual(last.query, ["after_seq": "7", "limit": "1"])
    }

    private let device = DeviceRegistration(token: "push_1", provider: .apns, platform: "ios", installId: "ins_12345678", locale: "vi")

    func testPutAndDeleteDevices() async throws {
        server.enqueue(.json(#"{"ok":true}"#))
        server.enqueue(.text("", status: 204))
        let put = try await api().putDevice(token: "tok", device: device)
        XCTAssertTrue(put)
        let p = last
        XCTAssertEqual(p.method, "PUT")
        XCTAssertEqual(p.path, "/widget/v1/sites/site_1/devices")
        XCTAssertEqual(p.header("x-visitor-token"), "tok")
        XCTAssertEqual(p.json, json(#"{"token":"push_1","provider":"apns","platform":"ios","install_id":"ins_12345678","locale":"vi"}"#))
        let del = try await api().deleteDevice(token: "tok", pushToken: "push_1")
        XCTAssertTrue(del)
        XCTAssertEqual(last.method, "DELETE")
        XCTAssertEqual(last.json, json(#"{"token":"push_1"}"#))
    }

    func testAGatewayWithoutTheDeviceEndpointIsTolerated() async throws {
        server.enqueue(.json(#"{"statusCode":404,"name":"not_found","message":"no"}"#, status: 404))
        server.enqueue(.json(#"{"statusCode":404,"name":"not_found","message":"no"}"#, status: 404))
        let put = try await api().putDevice(token: "tok", device: device)
        XCTAssertFalse(put)
        let del = try await api().deleteDevice(token: "tok", pushToken: "p")
        XCTAssertFalse(del)
    }

    func testErrorBodyMapsToCodeAndStatus() async {
        let e = await errorOf(.json(#"{"statusCode":401,"name":"invalid_app_key","message":"Unknown app key"}"#, status: 401))
        XCTAssertEqual(e?.code, "invalid_app_key")
        XCTAssertEqual(e?.status, 401)
        XCTAssertEqual(e?.message, "Unknown app key")
        XCTAssertTrue(e?.isAppKeyError ?? false)
        let revoked = await errorOf(.json(#"{"name":"app_key_revoked","message":"x"}"#, status: 403))
        XCTAssertTrue(revoked?.isAppKeyError ?? false)
        let token = await errorOf(.json(#"{"name":"invalid_visitor_token","message":"x"}"#, status: 401))
        XCTAssertTrue(token?.isTokenError ?? false)
    }

    func testNonJSONBodiesFallBackToAStatusDerivedCode() async {
        let bad = await errorOf(.text("<html>bad gateway</html>", status: 502))
        XCTAssertEqual(bad?.code, "server_error")
        let rl = await errorOf(.text("slow", status: 429))
        XCTAssertEqual(rl?.code, "rate_limit_exceeded")
        XCTAssertTrue(rl?.isRateLimit ?? false)
        XCTAssertTrue(rl?.isTransient ?? false)
        let v = await errorOf(.text("", status: 422))
        XCTAssertEqual(v?.code, "validation_error")
        let nf = await errorOf(.text("", status: 404))
        XCTAssertEqual(nf?.code, "not_found")
        let teapot = await errorOf(.text("", status: 418))
        XCTAssertEqual(teapot?.code, "http_error")
    }

    func testTransportFailuresAndTimeoutsBecomeNetworkError() async {
        let e = await errorOf(.failure(.networkConnectionLost))
        XCTAssertEqual(e?.code, "network_error")
        XCTAssertTrue(e?.isTransient ?? false)
        let t = await errorOf(.failure(.timedOut))
        XCTAssertEqual(t?.code, "network_error")
        XCTAssertEqual(t?.message, "The request timed out")
    }

    func testBadJSONInA200IsADecodeError() async {
        let e = await errorOf(.text("{nope", status: 200))
        XCTAssertEqual(e?.code, "decode_error")
    }

    func testResetRestoreAndOfflineMessage() async throws {
        server.enqueue(.json(#"{"visitor_token":"tok_new","visitor_id":"vis_9"}"#))
        let r = try await api().reset(token: "tok_old", installId: "ins_12345678")
        XCTAssertTrue(last.path.hasSuffix("/reset"))
        XCTAssertEqual(last.header("x-visitor-token"), "tok_old")
        XCTAssertEqual(last.json, json(#"{"install_id":"ins_12345678"}"#))
        XCTAssertEqual(r, ResetResult(visitorToken: "tok_new", visitorId: "vis_9"))

        server.enqueue(.json(#"{"visitor_token":"tok_r","visitor_id":"vis_r","conversation_id":"conv_r","conversation":{"id":"conv_r","status":"resolved"}}"#))
        let restored = try await api().restoreSession(linkToken: "link_1")
        XCTAssertEqual(last.json, json(#"{"token":"link_1"}"#))
        XCTAssertEqual(restored.conversation?.id, "conv_r")

        server.enqueue(.json(#"{"conversation":{"id":"conv_9","site_id":"site_1","visitor_id":"vis_1","status":"open","seq":1},"message_id":"m_9"}"#))
        let o = try await api().offlineMessage(token: "t", message: "hello", name: "", email: "a@b.test")
        XCTAssertEqual(last.json, json(#"{"email":"a@b.test","message":"hello"}"#))
        XCTAssertEqual(o.conversation.id, "conv_9")
        XCTAssertEqual(o.messageId, "m_9")
    }

    func testSendMessageAndLead() async throws {
        server.enqueue(.json(#"{"id":"m_1","seq":4,"duplicate":true}"#))
        let s = try await api().sendMessage(token: "t", conversationId: "c", clientId: "c1", content: "hi", attachments: [])
        XCTAssertEqual(last.json, json(#"{"client_id":"c1","content":"hi"}"#))
        XCTAssertEqual(s, SendResult(id: "m_1", seq: 4, duplicate: true))
        server.enqueue(.json(#"{"conversation_id":"c","visitor_id":"v"}"#))
        let l = try await api().lead(name: "An", fields: ["size": "L"])
        XCTAssertNil(last.header("x-visitor-token"))
        XCTAssertEqual(last.json, json(#"{"name":"An","fields":{"size":"L"}}"#))
        XCTAssertEqual(l.conversationId, "c")
    }

    func testUploadIsMultipartWithProgress() async throws {
        server.enqueue(.json(#"{"id":"f_1","name":"a.txt","size":5,"type":"text/plain"}"#))
        let progress = Locked<[(Int64, Int64)]>([])
        let a = try await api().upload(token: "t", data: Data("hello".utf8), filename: "a.txt", contentType: "text/plain") { sent, total in
            progress.withLock { $0.append((sent, total)) }
        }
        let req = last
        XCTAssertTrue(req.path.hasSuffix("/uploads"))
        XCTAssertTrue(req.header("content-type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        XCTAssertEqual(req.header("x-visitor-token"), "t")
        let body = req.bodyText
        XCTAssertTrue(body.contains("filename=\"a.txt\""))
        XCTAssertTrue(body.contains("name=\"file\""))
        XCTAssertTrue(body.contains("\r\n\r\nhello\r\n"))
        let p = progress.current
        XCTAssertFalse(p.isEmpty)
        XCTAssertEqual(p.last?.0, Int64(req.body.count))
        XCTAssertEqual(p.last?.1, Int64(req.body.count))
        XCTAssertEqual(a.id, "f_1")
    }
}

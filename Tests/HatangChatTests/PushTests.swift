import XCTest
@testable import HatangChat

final class PushTests: XCTestCase {
    func testRecognisesHatangPayloads() {
        XCTAssertTrue(HatangPush.isHatang(["hatang": "1", "conversation_id": "c1", "aps": ["alert": "x"]]))
        XCTAssertTrue(HatangPush.isHatang(["hatang": "true"]))
        XCTAssertTrue(HatangPush.isHatang(["hatang": 1]))
        XCTAssertTrue(HatangPush.isHatang(["hatang": true]))
        XCTAssertFalse(HatangPush.isHatang(["hatang": "0"]))
        XCTAssertFalse(HatangPush.isHatang(["type": "order_shipped"]))
        XCTAssertFalse(HatangPush.isHatang([:]))
    }

    func testReadsTheConversationId() {
        XCTAssertEqual(HatangPush.conversationId(["hatang": "1", "conversation_id": "c1"]), "c1")
        XCTAssertEqual(HatangPush.conversationId(["hatang": "1", "conversationId": "c2"]), "c2")
        XCTAssertNil(HatangPush.conversationId(["hatang": "1"]))
        XCTAssertNil(HatangPush.conversationId(["hatang": "1", "conversation_id": " "]))
    }

    func testAcceptsAPayloadNestedUnderData() {
        let json: [AnyHashable: Any] = ["data": #"{"hatang":"1","conversation_id":"c3","seq":7}"#, "from": "fcm"]
        XCTAssertTrue(HatangPush.isHatang(json))
        XCTAssertEqual(HatangPush.conversationId(json), "c3")
        XCTAssertEqual(HatangPush.payload(json)["seq"], "7")
        let dict: [AnyHashable: Any] = ["data": ["hatang": "1", "conversation_id": "c4"]]
        XCTAssertEqual(HatangPush.conversationId(dict), "c4")
        XCTAssertFalse(HatangPush.isHatang(["data": "not json"]))
        XCTAssertFalse(HatangPush.isHatang(["data": #"{"other":"1"}"#]))
        XCTAssertTrue(HatangPush.isHatang(["data": #"{"hatang":1}"#]))
        XCTAssertTrue(HatangPush.isHatang(["data": #"{"hatang":true}"#]))
    }

    func testMagicLinkTokens() {
        XCTAssertEqual(linkTokenFromSegments(["c", "abcdefghijkl"]), "abcdefghijkl")
        XCTAssertEqual(linkTokenFromSegments(["", "w", "c", "abcdefghijkl", ""]), "abcdefghijkl")
        XCTAssertNil(linkTokenFromSegments(["c", "short"]))
        XCTAssertNil(linkTokenFromSegments(["x", "abcdefghijkl"]))
        XCTAssertNil(linkTokenFromSegments([]))
        XCTAssertEqual(linkTokenFrom(URL(string: "https://chat.hatang.dev/c/abcdefghijkl")!), "abcdefghijkl")
        XCTAssertEqual(linkTokenFrom(URL(string: "myapp://open?hatang_restore=tok123")!), "tok123")
        XCTAssertNil(linkTokenFrom(URL(string: "https://example.com/products/1")!))
    }

    func testHexToken() {
        XCTAssertEqual(hexToken(Data([0x00, 0xAB, 0x10, 0xFF])), "00ab10ff")
    }
}

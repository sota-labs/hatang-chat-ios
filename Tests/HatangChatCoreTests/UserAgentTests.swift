import XCTest
@testable import HatangChatCore

final class UserAgentTests: XCTestCase {
    func testBrowserSummaries() {
        let cases: [(String, BrowserSummary)] = [
            ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36", BrowserSummary(browser: "Chrome", version: "140", os: "macOS")),
            ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0", BrowserSummary(browser: "Edge", version: "139", os: "Windows")),
            ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1", BrowserSummary(browser: "Safari", version: "18", os: "iOS")),
            ("Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0", BrowserSummary(browser: "Firefox", version: "131", os: "Linux")),
            ("Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Mobile Safari/537.36", BrowserSummary(browser: "Samsung Internet", version: "26", os: "Android")),
            ("curl/8.7.1", BrowserSummary(browser: "Browser", version: nil, os: "unknown OS")),
        ]
        for (ua, want) in cases { XCTAssertEqual(browserSummary(ua), want, ua) }
    }

    func testShortLocaleTagKeepsLanguageRegionWithin10Chars() {
        XCTAssertEqual(shortLocaleTag("vi-VN"), "vi-VN")
        XCTAssertEqual(shortLocaleTag("en-US-u-ca-gregory"), "en-US")
        XCTAssertEqual(shortLocaleTag("zh-Hant-TW-x-private"), "zh-TW")
        XCTAssertNil(shortLocaleTag(nil))
    }

    func testTheAppPayloadNeverExceedsTheGatewayLimits() {
        let ua = "Mozilla/5.0 " + String(repeating: "x", count: 200)
        let ctx = HatangAppInfo(
            appVersion: String(repeating: "1", count: 50),
            os: String(repeating: "web", count: 10),
            osVersion: ua,
            deviceModel: ua,
            deviceLocale: "en-US-u-ca-gregory-nu-latn"
        ).context(installId: "install-123456")
        XCTAssertLessThanOrEqual(ctx.version!.count, 40)
        XCTAssertLessThanOrEqual(ctx.os!.count, 20)
        XCTAssertEqual(ctx.osVersion?.count, 40)
        XCTAssertEqual(ctx.deviceModel?.count, 80)
        XCTAssertEqual(ctx.locale, "en-US")
    }

    func testIOSIdentityInSdkClientAndUserAgent() {
        let info = HatangAppInfo(appVersion: "1.4.0", buildNumber: "12", osVersion: "18.1", deviceModel: "iPhone15,2")
        XCTAssertEqual(info.os, "ios")
        XCTAssertEqual(info.sdk, "ios/\(sdkVersion)")
        XCTAssertEqual(info.client.sdk, "ios")
        XCTAssertEqual(info.client.version, sdkVersion)
        XCTAssertEqual(info.userAgent, "hatang-chat-ios/\(sdkVersion) (ios/18.1; protocol/1)")
        XCTAssertEqual(info.version, "1.4.0+12")
        XCTAssertEqual(HatangAppInfo().userAgent, "hatang-chat-ios/\(sdkVersion) (ios; protocol/1)")
        XCTAssertEqual(info.context(installId: "ins_12345678").toJSON().str("sdk"), "ios/\(sdkVersion)")
    }

    func testCurrentReadsTheSystem() {
        let info = HatangAppInfo.current()
        XCTAssertFalse((info.osVersion ?? "").isEmpty)
        XCTAssertNotNil(info.deviceModel)
    }
}

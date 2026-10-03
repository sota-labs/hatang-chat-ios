import Foundation

/// What a browser user agent says, reduced to what fits `app.os_version` and `app.device_model`.
public struct BrowserSummary: Sendable, Hashable {
    public var browser: String
    public var version: String?
    public var os: String

    public init(browser: String, version: String?, os: String) {
        self.browser = browser
        self.version = version
        self.os = os
    }
}

/// Reads the browser, its major version and the OS from a user agent string.
public func browserSummary(_ ua: String) -> BrowserSummary {
    func major(_ token: String) -> String? {
        guard let r = ua.range(of: token + "/") else { return nil }
        let digits = ua[r.upperBound...].prefix(while: { $0.isASCII && $0.isNumber })
        return digits.isEmpty ? nil : String(digits)
    }
    let browser: String
    let version: String?
    if ua.contains("SamsungBrowser/") {
        (browser, version) = ("Samsung Internet", major("SamsungBrowser"))
    } else if ua.contains("OPR/") {
        (browser, version) = ("Opera", major("OPR"))
    } else if ua.contains("Edg/") {
        (browser, version) = ("Edge", major("Edg"))
    } else if ua.contains("EdgiOS/") {
        (browser, version) = ("Edge", major("EdgiOS"))
    } else if ua.contains("FxiOS/") {
        (browser, version) = ("Firefox", major("FxiOS"))
    } else if ua.contains("Firefox/") {
        (browser, version) = ("Firefox", major("Firefox"))
    } else if ua.contains("CriOS/") {
        (browser, version) = ("Chrome", major("CriOS"))
    } else if ua.contains("Chrome/") {
        (browser, version) = ("Chrome", major("Chrome"))
    } else if ua.contains("Safari/") {
        (browser, version) = ("Safari", major("Version"))
    } else {
        (browser, version) = ("Browser", nil)
    }
    let os: String
    if ua.contains("iPhone") || ua.contains("iPad") || ua.contains("iPod") {
        os = "iOS"
    } else if ua.contains("Android") {
        os = "Android"
    } else if ua.contains("CrOS") {
        os = "ChromeOS"
    } else if ua.contains("Mac OS X") || ua.contains("Macintosh") {
        os = "macOS"
    } else if ua.contains("Windows") {
        os = "Windows"
    } else if ua.contains("Linux") {
        os = "Linux"
    } else {
        os = "unknown OS"
    }
    return BrowserSummary(browser: browser, version: version, os: os)
}

/// `value` cut to `max` characters (nil stays nil).
public func clampLength(_ value: String?, _ max: Int) -> String? {
    guard let v = value, v.count > max else { return value }
    return String(v.prefix(max))
}

/// A BCP 47 tag the gateway accepts (≤ 10 chars): extensions and scripts beyond language-region are
/// dropped (`en-US-u-ca-gregory` → `en-US`).
public func shortLocaleTag(_ tag: String?) -> String? {
    guard let tag, tag.count > 10 else { return tag }
    let parts = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
    let isRegion: (String) -> Bool = { p in
        (p.count == 2 && p.allSatisfy { $0.isASCII && $0.isLetter }) || (p.count == 3 && p.allSatisfy { $0.isASCII && $0.isNumber })
    }
    let region = parts.dropFirst().first(where: isRegion)
    let first = parts.first ?? tag
    let short = region.map { "\(first)-\($0)" } ?? first
    return clampLength(short, 10)
}

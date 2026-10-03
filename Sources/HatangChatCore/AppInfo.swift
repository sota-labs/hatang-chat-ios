import Foundation

/// SDK name reported to the gateway (`app.sdk`, `client.sdk`, the user agent).
public let sdkName = "ios"

/// What the SDK tells the gateway about the host app and device. `HatangAppInfo.current()` fills it from
/// the main bundle and the system; hosts may pass their own.
public struct HatangAppInfo: Sendable, Hashable {
    /// Host app version (`1.4.0`).
    public var appVersion: String?
    /// Host app build number (`CFBundleVersion`).
    public var buildNumber: String?
    /// `ios`, `android`, `web`, `macos`, `windows`, `linux` or `other`.
    public var os: String
    /// OS version (`18.1`).
    public var osVersion: String?
    /// Device model (`iPhone15,2`).
    public var deviceModel: String?
    /// Device language tag (`vi-VN`).
    public var deviceLocale: String?

    public init(
        appVersion: String? = nil,
        buildNumber: String? = nil,
        os: String = "ios",
        osVersion: String? = nil,
        deviceModel: String? = nil,
        deviceLocale: String? = nil
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.os = os
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.deviceLocale = deviceLocale
    }

    /// The running app: version and build from the main bundle, the OS version, the hardware model and
    /// the first preferred language.
    public static func current(bundle: Bundle = .main) -> HatangAppInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #if os(macOS)
        let os = "macos"
        #else
        let os = "ios"
        #endif
        return HatangAppInfo(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            os: os,
            osVersion: osVersion,
            deviceModel: hardwareModel(),
            deviceLocale: Locale.preferredLanguages.first
        )
    }

    /// Version with build number, as sent in `app.version` (`1.4.0+12`).
    public var version: String? {
        guard let v = appVersion else { return nil }
        guard let b = buildNumber, !b.isEmpty else { return v }
        return "\(v)+\(b)"
    }

    /// `ios/0.1.0`.
    public var sdk: String { "\(sdkName)/\(sdkVersion)" }

    /// The `User-Agent` for REST and socket calls: `hatang-chat-ios/0.1.0 (ios/18.1; protocol/1)`.
    public var userAgent: String {
        let platform = (osVersion?.isEmpty ?? true) ? os : "\(os)/\(osVersion!)"
        return "hatang-chat-\(sdkName)/\(sdkVersion) (\(platform); protocol/\(protocolVersion))"
    }

    /// The bootstrap/auth `app` payload for `installId`, with every field cut to the gateway's limits.
    public func context(installId: String, locale: String? = nil) -> AppContext {
        AppContext(
            installId: installId,
            version: clampLength(version, 40),
            sdk: clampLength(sdk, 60),
            os: clampLength(os, 20),
            osVersion: clampLength(osVersion, 40),
            deviceModel: clampLength(deviceModel, 80),
            locale: shortLocaleTag(locale ?? deviceLocale)
        )
    }

    /// The socket `client` payload.
    public var client: ClientInfo { ClientInfo(sdk: sdkName, version: sdkVersion) }
}

/// `utsname.machine` (`iPhone15,2`; `arm64` on the simulator and Macs).
func hardwareModel() -> String? {
    if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty { return sim }
    var u = utsname()
    guard uname(&u) == 0 else { return nil }
    let model = withUnsafeBytes(of: &u.machine) { raw in
        String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    return model.isEmpty ? nil : model
}

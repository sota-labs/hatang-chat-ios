import HatangChat
import Observation
import SwiftUI
import UIKit

/// Example settings and actions. Credentials come from (in order) launch arguments
/// (`-siteId X -appKey Y -baseURL Z`, read through UserDefaults), the settings form (saved in
/// UserDefaults), then the environment (`HATANG_SITE_ID`, `HATANG_APP_KEY`, `HATANG_BASE_URL`).
@MainActor
@Observable
final class Demo {
    var siteId: String
    var appKey: String
    var baseURL: String
    var status = "Not configured"

    private static let defaultBaseURL = "http://localhost:3002"

    init() {
        let d = UserDefaults.standard
        let env = ProcessInfo.processInfo.environment
        siteId = d.string(forKey: "siteId") ?? env["HATANG_SITE_ID"] ?? ""
        appKey = d.string(forKey: "appKey") ?? env["HATANG_APP_KEY"] ?? ""
        baseURL = d.string(forKey: "baseURL") ?? env["HATANG_BASE_URL"] ?? Self.defaultBaseURL
        configure()
    }

    var canConfigure: Bool { !siteId.isEmpty && !appKey.isEmpty && URL(string: baseURL) != nil }

    /// Saves the settings and (re)configures the SDK.
    func save() {
        let d = UserDefaults.standard
        d.set(siteId, forKey: "siteId")
        d.set(appKey, forKey: "appKey")
        d.set(baseURL, forKey: "baseURL")
        configure()
    }

    func configure() {
        guard canConfigure, let url = URL(string: baseURL) else {
            status = "Enter a site id and app key in Settings"
            return
        }
        // `-themeMode system|dark|light` overrides the site's light/dark setting (handy for screenshots).
        let mode: HatangChatThemeMode = switch UserDefaults.standard.string(forKey: "themeMode") {
        case "system": .system
        case "dark": .dark
        case "light": .light
        default: .site
        }
        HatangChat.configure(siteId: siteId, appKey: appKey, baseURL: url, themeMode: mode, logger: .console)
        status = "Configured \(siteId)"
    }

    func identify() async {
        guard HatangChat.isConfigured else { return }
        do {
            try await HatangChat.identify(HatangUser(userId: "ios-demo-1", email: "ios-demo@example.com", name: "iOS Demo"))
            status = "Identified as iOS Demo"
        } catch {
            status = "Identify failed: \(error.localizedDescription)"
        }
    }

    func reset() async {
        guard HatangChat.isConfigured else { return }
        await HatangChat.reset()
        status = "Reset: new visitor"
    }

    func send(_ text: String) async {
        guard HatangChat.isConfigured else { return }
        let engine = HatangChat.engine
        await engine.send(text)
        // An away site that wants an email first shows the pre-chat form instead: answer it like a visitor.
        if engine.currentState.needsEmail {
            await engine.submitOfflineForm(name: "iOS Demo", email: "ios-demo@example.com")
        }
        status = "Sent “\(text)”"
    }

    func enablePush() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        status = granted ? "Push: registering…" : "Push: permission denied"
    }

    /// Automation links: `hatangexample://open`, `://inbox`, `://identify`, `://reset`, `://close`,
    /// `://send?text=…`, `://configure?siteId=…&appKey=…&baseURL=…`; magic links restore the session.
    func handle(_ url: URL) {
        if let token = HatangChat.linkToken(from: url) {
            Task {
                do {
                    try await HatangChat.restoreSession(token)
                    HatangChat.present()
                } catch {
                    status = "Restore failed: \(error.localizedDescription)"
                }
            }
            return
        }
        guard url.scheme == "hatangexample" else { return }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, b in b }
        )
        switch url.host() {
        case "open": HatangChat.present(conversationId: query["conversation"])
        case "inbox": HatangChat.presentInbox()
        case "close": HatangChat.dismiss()
        case "identify": Task { await identify() }
        case "reset": Task { await reset() }
        case "send": Task { await send(query["text"] ?? "Hello from iOS") }
        case "configure":
            if let v = query["siteId"] { siteId = v }
            if let v = query["appKey"] { appKey = v }
            if let v = query["baseURL"] { baseURL = v }
            save()
        default: status = "Unknown link \(url.absoluteString)"
        }
    }
}

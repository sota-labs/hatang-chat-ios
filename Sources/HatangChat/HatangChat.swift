#if os(iOS)
import HatangChatCore
import SwiftUI
import UIKit

/// Entry point of the Hatang chat SDK. Call `configure` once (at launch), then `present` the chat,
/// `identify` the user and observe `model` / `unreadCount` / `events`.
///
/// ```swift
/// HatangChat.configure(siteId: "site_…", appKey: "hak_…")
/// HatangChat.present()
/// ```
@MainActor
public enum HatangChat {
    /// The production gateway.
    public static let defaultBaseURL = URL(string: "https://chat.hatang.dev")!

    private final class Instance {
        let engine: ChatEngine
        let api: WidgetAPI
        let logger: HatangLogger
        let openOnProactiveMessage: Bool
        var lifecycle: AppLifecycle?
        var tasks: [Task<Void, Never>] = []

        init(engine: ChatEngine, api: WidgetAPI, logger: HatangLogger, openOnProactiveMessage: Bool) {
            self.engine = engine
            self.api = api
            self.logger = logger
            self.openOnProactiveMessage = openOnProactiveMessage
        }
    }

    private static var current: Instance?
    private static weak var presented: UIViewController?
    private static var navigator: ChatNavigator?
    /// A chat requested while the app was not active ("" = the active conversation).
    private static var parked: String?
    private static var pendingPushToken: Data?

    /// The chat state for SwiftUI (an idle state before `configure`). Follows re-configuration.
    public static let model = HatangChatModel()

    /// `configure` has run.
    public static var isConfigured: Bool { current != nil }

    /// The state machine (advanced hosts). Crashes when `configure` has not run.
    public static var engine: ChatEngine {
        guard let e = current?.engine else { preconditionFailure("HatangChat.configure() has not been called") }
        return e
    }

    /// Messages received while the chat was not on screen (for badges). Observable through `model`.
    public static var unreadCount: Int { model.unread }

    /// The current session (visitor, conversation, locale).
    public static var session: HatangSession { model.session }

    /// Host-facing events (ready, opened, closed, messages, status, conversions, session changes,
    /// outdated) of the current engine. Subscribe after `configure`.
    public static var events: AsyncStream<HatangEvent> {
        current?.engine.events() ?? AsyncStream { $0.finish() }
    }

    // MARK: - Setup

    /// Configures the SDK. Calling it again replaces the previous engine. With `autoConnect` the SDK
    /// bootstraps and connects in the background right away.
    ///
    /// - Parameters:
    ///   - siteId: the site (`site_…`).
    ///   - appKey: the site app key (`hak_…`, from the website's Mobile apps tab in the dashboard).
    ///   - baseURL: gateway URL.
    ///   - locale: force a language (otherwise: the stored choice, the site default, then the device).
    ///   - themeMode: how light or dark is chosen.
    ///   - theme: light theme override (default: from the site's brand colour).
    ///   - darkTheme: dark theme override.
    ///   - strings: wording overrides per locale.
    ///   - autoConnect: bootstrap and connect right away.
    ///   - openOnProactiveMessage: show the chat when the team starts a conversation with "open on the
    ///     visitor's device" (at once when the app is active, else when it becomes active).
    ///   - logger: where the SDK logs (`.console` while integrating).
    ///   - appInfo: app and device details override (default: `HatangAppInfo.current()`).
    ///   - commerce: how purchases from chat cards are handled.
    public static func configure(
        siteId: String,
        appKey: String,
        baseURL: URL = defaultBaseURL,
        locale: HatangLocale? = nil,
        themeMode: HatangChatThemeMode = .site,
        theme: HatangChatTheme? = nil,
        darkTheme: HatangChatTheme? = nil,
        strings: [HatangLocale: HatangChatStrings]? = nil,
        autoConnect: Bool = true,
        openOnProactiveMessage: Bool = true,
        logger: HatangLogger = .silent,
        appInfo: HatangAppInfo? = nil,
        commerce: HatangCommerce = .standard
    ) {
        precondition(!siteId.trimmingCharacters(in: .whitespaces).isEmpty, "siteId must not be empty")
        precondition(!appKey.trimmingCharacters(in: .whitespaces).isEmpty, "appKey must not be empty")
        dispose()
        let info = appInfo ?? HatangAppInfo.current()
        let keychain = KeychainStore(logger: logger)
        let defaults = UserDefaults.standard
        // Keychain items outlive an uninstall; a reinstall starts as a fresh visitor like on Android.
        let marker = "hatang_chat.installed"
        if !defaults.bool(forKey: marker) {
            keychain.removeAll()
            defaults.set(true, forKey: marker)
        }
        let api = WidgetAPI(baseURL: baseURL.absoluteString, siteId: siteId, appKey: appKey, userAgent: info.userAgent)
        let engine = ChatEngine(
            api: api,
            connector: URLSessionSocketConnector(userAgent: info.userAgent),
            store: SessionStore(siteId: siteId, secure: keychain, prefs: UserDefaultsStore(defaults: defaults)),
            appInfo: info,
            logger: logger,
            preferredLocale: locale?.code,
            openOnProactiveMessage: openOnProactiveMessage
        )
        let instance = Instance(engine: engine, api: api, logger: logger, openOnProactiveMessage: openOnProactiveMessage)
        current = instance
        model.appearance = Appearance(themeMode: themeMode, theme: theme, darkTheme: darkTheme, strings: strings)
        model.commerce = commerce
        model.logger = logger
        model.bind(engine)

        let lifecycle = AppLifecycle(
            onChange: { foreground in Task { await engine.setForeground(foreground) } },
            onActive: { openParked() }
        )
        instance.lifecycle = lifecycle
        let foreground = lifecycle.isForeground
        let requests = engine.openRequests()
        instance.tasks.append(Task { @MainActor in
            for await id in requests { onOpenRequest(id) }
        })
        instance.tasks.append(Task {
            await engine.setForeground(foreground)
            if autoConnect { await engine.start() }
        })
        if let token = pendingPushToken {
            pendingPushToken = nil
            Task { await engine.setPushToken(apnsDeviceToken: token) }
        }
    }

    /// Releases the engine and every resource; `configure` again to use the SDK afterwards.
    public static func dispose() {
        guard let i = current else { return }
        current = nil
        i.lifecycle?.detach()
        i.tasks.forEach { $0.cancel() }
        model.bind(nil)
        let engine = i.engine
        let api = i.api
        Task {
            await engine.dispose()
            api.close()
        }
    }

    /// Bootstraps and connects (after `autoConnect: false` or `disconnect`).
    public static func connect() async {
        await current?.engine.connect()
    }

    /// Closes the socket; the SDK stays configured.
    public static func disconnect() async {
        await current?.engine.stop()
    }

    private static func requireEngine() throws -> ChatEngine {
        guard let e = current?.engine else {
            throw HatangError(code: "not_configured", message: "HatangChat.configure() has not been called")
        }
        return e
    }

    // MARK: - Session

    /// Attaches the host user's identity. Pass a `hash` (HMAC-SHA256 of the user id with the site's
    /// identity secret, computed on your server) for verified identities. Throws `HatangError`.
    public static func identify(_ user: HatangUser) async throws {
        try await requireEngine().identify(user)
    }

    /// Attaches custom attributes shown to agents.
    public static func setData(_ data: JSONObject) async throws {
        try await requireEngine().setData(data)
    }

    /// Records a custom event on the active conversation.
    public static func pushEvent(_ name: String, data: JSONObject? = nil) {
        guard let e = current?.engine else { return }
        Task { await e.pushEvent(name, data: data) }
    }

    /// Switches the language.
    public static func setLocale(_ locale: HatangLocale) async {
        await current?.engine.setLocale(locale)
    }

    /// Reports the screen the app shows (live board and page views).
    public static func setScreen(_ name: String, params: [String: String]? = nil) {
        guard let e = current?.engine else { return }
        Task { await e.setScreen(name, params: params) }
    }

    /// Shows a local-only assistant bubble (never sent to the gateway).
    public static func showMessage(_ text: String, senderName: String? = nil) {
        guard let e = current?.engine else { return }
        Task { await e.showLocalMessage(text, senderName: senderName) }
    }

    /// Forgets this visitor (sign-out): fresh visitor, old token revoked. Failures are logged.
    public static func reset() async {
        guard let i = current else { return }
        do {
            try await i.engine.reset()
        } catch {
            i.logger.warn("reset failed: \(error)")
        }
    }

    /// Restores the session behind a "we replied" magic-link token (see `linkToken(from:)`).
    public static func restoreSession(_ linkToken: String) async throws {
        try await requireEngine().restoreSession(linkToken)
    }

    /// The restore token inside a magic link: a `hatang_restore` query parameter or a `…/c/<token>` path;
    /// nil for other URLs.
    public nonisolated static func linkToken(from url: URL) -> String? {
        linkTokenFrom(url)
    }

    // MARK: - UI

    /// Presents the chat modally (the active conversation, or `conversationId`) over `from`, or over the
    /// key window's top-most view controller. When the chat is already on screen it switches to
    /// `conversationId` instead.
    public static func present(from: UIViewController? = nil, conversationId: String? = nil) {
        show(.conversation(conversationId), from: from)
    }

    /// Presents the visitor's conversation list; tapping one opens it, back returns to the list.
    public static func presentInbox(from: UIViewController? = nil) {
        show(.inbox, from: from)
    }

    /// Dismisses the chat presented by `present`, `presentInbox` or `handleNotification`.
    public static func dismiss() {
        presented?.dismiss(animated: true)
        presented = nil
        navigator = nil
    }

    /// A chat presented by the SDK is on screen.
    public static var isPresented: Bool { presented?.presentingViewController != nil }

    private static func show(_ start: ChatNavigator.Start, from: UIViewController?) {
        guard current != nil else {
            assertionFailure("HatangChat.configure() has not been called")
            return
        }
        if isPresented, let nav = navigator {
            nav.go(to: start)
            return
        }
        guard let host = from ?? topViewController() else {
            // No window yet (cold start from a notification): show it once the app is active.
            if case .conversation(let id) = start { parked = id ?? "" }
            return
        }
        let nav = ChatNavigator(start: start)
        let vc = HatangChatViewController(navigator: nav, model: model)
        vc.onDismiss = {
            if presented === vc {
                presented = nil
                navigator = nil
            }
        }
        presented = vc
        navigator = nav
        host.present(vc, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.sorted { a, _ in a.activationState == .foregroundActive }.flatMap(\.windows)
        guard let root = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else { return nil }
        var top = root
        while true {
            if let p = top.presentedViewController, !p.isBeingDismissed {
                top = p
            } else if let n = top as? UINavigationController, let v = n.visibleViewController {
                if v === top { break }
                top = v
            } else if let t = top as? UITabBarController, let s = t.selectedViewController {
                top = s
            } else {
                break
            }
        }
        return top
    }

    private static func onOpenRequest(_ conversationId: String) {
        guard let i = current, i.openOnProactiveMessage, !isPresented else { return }
        if i.lifecycle?.isActive == true {
            present(conversationId: conversationId)
        } else {
            parked = conversationId
        }
    }

    private static func openParked() {
        guard let id = parked else { return }
        parked = nil
        if !isPresented { present(conversationId: id.isEmpty ? nil : id) }
    }

    // MARK: - Push

    /// Registers the APNs device token from
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` (sent as lower-case hex with
    /// provider `apns`). Safe before `configure` and before the SDK is ready: registration is deferred and
    /// repeated when the visitor or the app version changes.
    public static func setPushToken(_ deviceToken: Data) async {
        guard let e = current?.engine else {
            pendingPushToken = deviceToken
            return
        }
        await e.setPushToken(apnsDeviceToken: deviceToken)
    }

    /// Registers a Firebase Cloud Messaging token instead of an APNs one (apps that already use FCM).
    public static func setPushToken(fcmToken: String) async {
        await current?.engine.setPushToken(fcmToken, provider: .fcm)
    }

    /// Unregisters the push token (sign-out).
    public static func clearPushToken() async {
        pendingPushToken = nil
        await current?.engine.clearPushToken()
    }

    /// `true` when a notification's `userInfo` came from Hatang (`hatang: "1"`).
    public nonisolated static func isHatangNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        HatangPush.isHatang(userInfo)
    }

    /// The conversation a Hatang notification points at, if any.
    public nonisolated static func conversationId(of userInfo: [AnyHashable: Any]) -> String? {
        HatangPush.conversationId(userInfo)
    }

    /// Opens the conversation a Hatang notification points at (call it from
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)`; callable from any thread). Returns
    /// false for foreign payloads. Starts the engine when it is not running yet (cold start) and shows the
    /// chat once the app is active.
    @discardableResult
    public nonisolated static func handleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard HatangPush.isHatang(userInfo) else { return false }
        let id = HatangPush.conversationId(userInfo)
        Task { @MainActor in openFromNotification(id) }
        return true
    }

    private static func openFromNotification(_ id: String?) {
        guard let i = current else { return }
        let engine = i.engine
        Task {
            if !engine.isStarted { await engine.start() }
        }
        if i.lifecycle?.isActive == true {
            present(conversationId: id)
        } else {
            // Tapped from the background: the window is not active yet.
            parked = id ?? ""
        }
    }
}
#endif

import Foundation

/// What the SDK remembers between launches for one site.
public struct StoredSession: Sendable, Hashable {
    /// Visitor token (secure storage).
    public var token: String?
    /// Active conversation id.
    public var conversationId: String?
    /// Highest seq the app has seen.
    public var lastSeq: Int
    /// Locale the host or user chose.
    public var locale: String?
    /// Email the visitor gave.
    public var email: String?
    /// Name the visitor gave.
    public var name: String?
    /// Push token last handed to `setPushToken`.
    public var pushToken: String?
    /// `fcm` or `apns`.
    public var pushProvider: String?
    /// App version the push token was registered under.
    public var pushAppVersion: String?

    public init(
        token: String? = nil,
        conversationId: String? = nil,
        lastSeq: Int = 0,
        locale: String? = nil,
        email: String? = nil,
        name: String? = nil,
        pushToken: String? = nil,
        pushProvider: String? = nil,
        pushAppVersion: String? = nil
    ) {
        self.token = token
        self.conversationId = conversationId
        self.lastSeq = lastSeq
        self.locale = locale
        self.email = email
        self.name = name
        self.pushToken = pushToken
        self.pushProvider = pushProvider
        self.pushAppVersion = pushAppVersion
    }

    /// The same session without a conversation (and so without a `lastSeq`).
    public func withoutConversation() -> StoredSession {
        var s = self
        s.conversationId = nil
        s.lastSeq = 0
        return s
    }

    /// Nothing stored yet.
    public static let empty = StoredSession()
}

/// Persists a `StoredSession` under `hatang_chat.<siteId>.*`: the token in the `secure` store, everything
/// else in the `prefs` store.
public struct SessionStore: Sendable {
    /// The site.
    public let siteId: String
    private let secure: any KeyValueStore
    private let prefs: any KeyValueStore

    public init(siteId: String, secure: any KeyValueStore, prefs: any KeyValueStore) {
        self.siteId = siteId
        self.secure = secure
        self.prefs = prefs
    }

    private func k(_ name: String) -> String { "hatang_chat.\(siteId).\(name)" }

    /// The token's key (secure storage).
    public var tokenKey: String { k("token") }

    /// The install id store (prefs).
    public var installStore: any KeyValueStore { prefs }

    /// Loads everything. A store that fails reads as "nothing stored".
    public func load() async -> StoredSession {
        let token = (try? await secure.get(tokenKey)) ?? nil
        func p(_ name: String) async -> String? { (try? await prefs.get(k(name))) ?? nil }
        return StoredSession(
            token: token,
            conversationId: await p("conversation_id"),
            lastSeq: (await p("last_seq")).flatMap { Int($0) } ?? 0,
            locale: await p("locale"),
            email: await p("email"),
            name: await p("name"),
            pushToken: await p("push_token"),
            pushProvider: await p("push_provider"),
            pushAppVersion: await p("push_app_version")
        )
    }

    /// Writes every field of `s` (nils delete). Secure storage failures are left to the platform layer.
    public func save(_ s: StoredSession) async throws {
        try? await put(secure, tokenKey, s.token)
        try await put(prefs, k("conversation_id"), s.conversationId)
        try await put(prefs, k("last_seq"), s.lastSeq == 0 ? nil : String(s.lastSeq))
        try await put(prefs, k("locale"), s.locale)
        try await put(prefs, k("email"), s.email)
        try await put(prefs, k("name"), s.name)
        try await put(prefs, k("push_token"), s.pushToken)
        try await put(prefs, k("push_provider"), s.pushProvider)
        try await put(prefs, k("push_app_version"), s.pushAppVersion)
    }

    private func put(_ store: any KeyValueStore, _ key: String, _ value: String?) async throws {
        if let value { try await store.set(key, value) } else { try await store.remove(key) }
    }
}

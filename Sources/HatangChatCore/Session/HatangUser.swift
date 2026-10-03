import Foundation

/// The identity a host app attaches to the visitor with `identify`.
///
/// `hash` is the HMAC-SHA256 (hex) of `userId` (or the email when there is no user id) computed on the
/// host's server with the site's identity secret; it proves the identity so the visitor can be merged
/// with earlier sessions.
public struct HatangUser: Sendable, Hashable {
    /// The host app's user id.
    public var userId: String?
    /// Email.
    public var email: String?
    /// Display name.
    public var name: String?
    /// Phone.
    public var phone: String?
    /// Identity HMAC from the host's server.
    public var hash: String?
    /// Custom attributes shown to agents (strings, numbers, booleans, lists and maps of them).
    public var data: JSONObject?

    public init(userId: String? = nil, email: String? = nil, name: String? = nil, phone: String? = nil, hash: String? = nil, data: JSONObject? = nil) {
        self.userId = userId
        self.email = email
        self.name = name
        self.phone = phone
        self.hash = hash
        self.data = data
    }

    /// Nothing to send.
    public var isEmpty: Bool {
        userId == nil && email == nil && name == nil && phone == nil && (data?.isEmpty ?? true)
    }
}

/// Push providers a device token can come from.
public enum PushProvider: String, Sendable, Hashable, CaseIterable {
    /// Firebase Cloud Messaging.
    case fcm
    /// Apple Push Notification service (direct).
    case apns

    /// The wire value.
    public var code: String { rawValue }

    /// Parses the wire value.
    public static func tryParse(_ s: String?) -> PushProvider? {
        s.flatMap(PushProvider.init(rawValue:))
    }
}

import Foundation

/// An error reported by the Hatang gateway (REST or socket) or by the SDK itself.
///
/// `code` is the stable slug the gateway uses (`invalid_app_key`, `rate_limit_exceeded`,
/// `validation_error`, ...). SDK-side failures use `network_error`, `timeout`, `closed` and
/// `decode_error`. `message` is English and meant for logs; the UI translates `code` instead.
public struct HatangError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    /// Stable error slug.
    public var code: String
    /// English message for logs.
    public var message: String
    /// HTTP status when the error came from a REST call.
    public var status: Int?

    public init(code: String, message: String, status: Int? = nil) {
        self.code = code
        self.message = message
        self.status = status
    }

    /// The gateway asked the client to slow down.
    public var isRateLimit: Bool { code == "rate_limit_exceeded" }

    /// The app key is missing, wrong or revoked: no retry will help.
    public var isAppKeyError: Bool { code == "invalid_app_key" || code == "app_key_revoked" }

    /// The visitor token is no longer accepted (reset elsewhere, revoked).
    public var isTokenError: Bool { code == "invalid_visitor_token" }

    /// Worth retrying later (transport trouble, rate limits, server errors).
    public var isTransient: Bool {
        code == "network_error" || code == "timeout" || code == "closed" || isRateLimit || (status ?? 0) >= 500
    }

    public var description: String {
        "HatangError(\(code)\(status.map { " \($0)" } ?? ""): \(message))"
    }

    public var errorDescription: String? { message }

    /// A request that never reached the gateway (DNS, TLS, offline).
    public static func network(_ message: String) -> HatangError {
        HatangError(code: "network_error", message: message)
    }

    /// A socket request that received no reply in time.
    public static var timeout: HatangError {
        HatangError(code: "timeout", message: "The request timed out")
    }

    /// A socket request whose connection closed before a reply came.
    public static var closed: HatangError {
        HatangError(code: "closed", message: "The connection closed before a reply arrived")
    }
}

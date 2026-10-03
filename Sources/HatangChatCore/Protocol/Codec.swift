import Foundation

/// The wire protocol version this SDK speaks.
public let protocolVersion = 1

/// Size limits the gateway enforces.
public enum Limits {
    /// Largest frame in bytes.
    public static let frameBytes = 16 * 1024
    /// Longest visitor message.
    public static let visitorText = 4000
    /// Longest agent message.
    public static let agentText = 10000
    /// Attachments per message.
    public static let attachmentsPerMessage = 5
    /// Largest attachment in bytes.
    public static let attachmentBytes = 10 * 1024 * 1024
    /// Largest custom data payload in bytes.
    public static let customDataBytes = 8 * 1024
}

/// Socket close codes the gateway uses.
public enum CloseCodes {
    /// No auth frame within 5 s of connecting: reconnect, auth first.
    public static let authTimeout = 4001
    /// Auth refused, or the session was revoked: bootstrap a fresh visitor.
    public static let authFailed = 4003
    /// The client's protocol version is older than the gateway supports: stop, ask for an update.
    public static let protocolOutdated = 4004
    /// A `session` frame carried a new visitor token; reconnect at once.
    public static let sessionReplaced = 4005
    /// The SDK closed the socket because building the auth payload failed.
    public static let clientAuthError = 4000
}

/// Serialises `frame` for the wire.
public func encodeFrame(_ frame: ClientFrame, id: String? = nil) -> String {
    JSONValue.object(frame.toJSON(id: id)).jsonText
}

/// Parses a frame from the wire. Throws `HatangError` (`decode_error`) when `raw` is not a JSON object;
/// unknown frame types decode to `.unknown`.
public func decodeFrame(_ raw: String) throws -> ServerFrame {
    guard let parsed = JSONValue.parse(raw) else {
        throw HatangError(code: "decode_error", message: "Bad frame: not JSON")
    }
    guard let o = parsed.objectValue else {
        throw HatangError(code: "decode_error", message: "Frame is not an object")
    }
    return ServerFrame(json: o)
}

/// Like `decodeFrame` but returns nil instead of throwing.
public func tryDecodeFrame(_ raw: String) -> ServerFrame? {
    try? decodeFrame(raw)
}

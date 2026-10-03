import Foundation

/// A file the visitor is sending: its bytes, name and MIME type. Built by the SDK's pickers (or by the
/// host) and handed to `ChatEngine.attach`.
public struct UploadSource: Sendable, Hashable, CustomStringConvertible {
    /// File contents.
    public var data: Data
    /// File name shown to the team.
    public var name: String
    /// MIME type (`image/jpeg`, `application/pdf`, …).
    public var mimeType: String

    public init(data: Data, name: String, mimeType: String) {
        self.data = data
        self.name = name
        self.mimeType = mimeType
    }

    /// Size in bytes.
    public var size: Int { data.count }

    /// A picture (shown as a thumbnail).
    public var isImage: Bool { mimeType.hasPrefix("image/") }

    public var description: String { "UploadSource(\(name), \(mimeType), \(size) bytes)" }
}

/// MIME types the gateway accepts (the same list as the server's upload allow-list).
public let uploadMimeTypes: Set<String> = [
    "image/png", "image/jpeg", "image/gif", "image/webp", "image/heic", "image/heif",
    "application/pdf", "text/plain", "text/csv", "application/zip",
    "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "video/mp4", "audio/mp4", "audio/mpeg",
]

private let mimeByExtension: [String: String] = [
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
    "heic": "image/heic", "heif": "image/heif", "pdf": "application/pdf", "txt": "text/plain", "csv": "text/csv",
    "zip": "application/zip", "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xls": "application/vnd.ms-excel", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "mp4": "video/mp4", "m4a": "audio/mp4", "mp3": "audio/mpeg",
]

/// MIME type for a file name, from its extension; nil when the gateway would refuse it.
public func mimeTypeForName(_ name: String) -> String? {
    guard let dot = name.lastIndex(of: ".") else { return nil }
    return mimeByExtension[name[name.index(after: dot)...].lowercased()]
}

/// The upload behind a pending attachment message.
public struct PendingUpload: Sendable, Hashable {
    /// What is being sent (kept for the preview and for retries).
    public var source: UploadSource
    /// 0...1 while the bytes go out.
    public var progress: Double
    /// The server's file id once uploaded.
    public var uploadedId: String?

    public init(source: UploadSource, progress: Double = 0, uploadedId: String? = nil) {
        self.source = source
        self.progress = progress
        self.uploadedId = uploadedId
    }

    /// The bytes reached the server.
    public var done: Bool { uploadedId != nil }
}

/// An outgoing message that has no ack yet (or failed).
public struct PendingMessage: Sendable, Hashable {
    /// Optimistic id sent as `client_id`.
    public var clientId: String
    /// Text.
    public var content: String
    /// When it was queued.
    public var createdAt: Date
    /// Upload ids attached.
    public var attachments: [String]
    /// The file being uploaded for this message, if it carries one.
    public var upload: PendingUpload?
    /// The send failed (tap to retry).
    public var failed: Bool
    /// Why it failed.
    public var errorCode: String?

    public init(clientId: String, content: String, createdAt: Date, attachments: [String] = [], upload: PendingUpload? = nil, failed: Bool = false, errorCode: String? = nil) {
        self.clientId = clientId
        self.content = content
        self.createdAt = createdAt
        self.attachments = attachments
        self.upload = upload
        self.failed = failed
        self.errorCode = errorCode
    }
}

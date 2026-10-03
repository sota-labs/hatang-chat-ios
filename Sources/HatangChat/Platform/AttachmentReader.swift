#if os(iOS)
import Foundation
import HatangChatCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Reads picked photos and files into `UploadSource`s (HEIC → JPEG, photos scaled to 2048 px, the 10 MB
/// limit enforced). Work happens off the main actor.
enum AttachmentReader {
    /// Content types offered by the file picker (the gateway's allow-list).
    static let fileTypes: [UTType] = {
        var types: [UTType] = [.image, .pdf, .plainText, .commaSeparatedText, .zip, .mpeg4Movie, .mpeg4Audio, .mp3]
        let extra = ["com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document", "com.microsoft.excel.xls", "org.openxmlformats.spreadsheetml.sheet"]
        types += extra.compactMap { UTType($0) }
        return types
    }()

    /// A photo from the PhotosPicker.
    static func read(_ item: PhotosPickerItem) async throws -> UploadSource {
        let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? item.supportedContentTypes.first
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw HatangError(code: "read_failed", message: "Could not load the photo")
        }
        let ext = type?.preferredFilenameExtension ?? "jpg"
        let base = item.itemIdentifier.map { "IMG_\($0.prefix(8).filter { $0.isLetter || $0.isNumber })" } ?? "IMG_\(Int(Date().timeIntervalSince1970))"
        let name = "\(base).\(ext)"
        let mime = AttachmentPreparer.mimeType(name: name, type: type)
        return try await Task.detached(priority: .userInitiated) {
            try AttachmentPreparer.prepare(data, name: name, mimeType: mime)
        }.value
    }

    /// A file from `.fileImporter` (security-scoped URL).
    static func read(_ url: URL) async throws -> UploadSource {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
            let name = values?.name ?? url.lastPathComponent
            let mime = AttachmentPreparer.mimeType(name: name, type: values?.contentType ?? UTType(filenameExtension: url.pathExtension))
            // Images may shrink below the limit after re-encoding; anything else is refused before reading.
            if !mime.hasPrefix("image/"), let size = values?.fileSize, size > Limits.attachmentBytes {
                throw AttachmentPreparer.tooLarge
            }
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw HatangError(code: "read_failed", message: "Could not read \(name): \(error.localizedDescription)")
            }
            return try AttachmentPreparer.prepare(data, name: name, mimeType: mime)
        }.value
    }
}
#endif

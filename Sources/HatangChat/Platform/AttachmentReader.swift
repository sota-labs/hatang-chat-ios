#if os(iOS)
import Foundation
import HatangChatCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Reads picked photos, videos and files into `UploadSource`s (HEIC → JPEG, photos scaled to 2048 px,
/// videos compressed to an H.264 mp4, the 10 MB / 25 MB limits enforced). Work happens off the main actor.
enum AttachmentReader {
    /// Content types offered by the file picker (the gateway's allow-list).
    static let fileTypes: [UTType] = {
        var types: [UTType] = [.image, .pdf, .plainText, .commaSeparatedText, .zip, .mpeg4Movie, .quickTimeMovie, .mpeg4Audio, .mp3]
        let extra = ["com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document", "com.microsoft.excel.xls", "org.openxmlformats.spreadsheetml.sheet"]
        types += extra.compactMap { UTType($0) }
        return types
    }()

    /// What the PhotosPicker offers: photos and videos.
    static let pickerFilter: PHPickerFilter = .any(of: [.images, .videos])

    /// A photo or video from the PhotosPicker.
    static func read(_ item: PhotosPickerItem) async throws -> UploadSource {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) && !item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
            return try await readVideo(item)
        }
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

    /// A video from the PhotosPicker, loaded as a file and compressed to mp4 so a typical clip fits 25 MB.
    private static func readVideo(_ item: PhotosPickerItem) async throws -> UploadSource {
        guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
            throw HatangError(code: "read_failed", message: "Could not load the video")
        }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        let base = item.itemIdentifier.map { "VID_\($0.prefix(8).filter { $0.isLetter || $0.isNumber })" } ?? "VID_\(Int(Date().timeIntervalSince1970))"
        let data = try await VideoExport.mp4(from: movie.url)
        return try AttachmentPreparer.prepare(data, name: "\(base).mp4", mimeType: "video/mp4")
    }

    /// A file from `.fileImporter` (security-scoped URL).
    static func read(_ url: URL) async throws -> UploadSource {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
            let name = values?.name ?? url.lastPathComponent
            let mime = AttachmentPreparer.mimeType(name: name, type: values?.contentType ?? UTType(filenameExtension: url.pathExtension))
            // A .mov, or an mp4 over 25 MB, is re-encoded as a smaller mp4 (the gateway plays mp4 everywhere).
            if isVideoUpload(mimeType: mime, name: name),
               mime == "video/quicktime" || (values?.fileSize ?? 0) > Limits.videoBytes {
                let data = try await VideoExport.mp4(from: url)
                return try AttachmentPreparer.prepare(data, name: ImageScaling.withExtension(name, "mp4"), mimeType: "video/mp4")
            }
            // Images may shrink below the limit after re-encoding; anything else is refused before reading.
            if !mime.hasPrefix("image/"), let size = values?.fileSize, size > attachmentLimit(mimeType: mime, name: name) {
                throw attachmentTooLargeError(mimeType: mime, name: name)
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

/// A picked movie, copied out of the picker's temporary file (which goes away after the import closure).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("hatang-pick-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
#endif

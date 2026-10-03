import Foundation
import HatangChatCore
import ImageIO
import UniformTypeIdentifiers

/// Sizing rules and the ImageIO pipeline for outgoing photos (no UIKit, so it runs in unit tests on macOS).
enum ImageScaling {
    /// Longest side of a photo after preparation.
    static let maxSide = 2048
    /// JPEG quality after preparation.
    static let jpegQuality = 0.85
    /// Photos above this size are re-encoded even when already JPEG or WebP.
    static let recompressAbove = 2 * 1024 * 1024

    /// `width`×`height` scaled down (never up) so the longer side is at most `maxSide`.
    static func fit(_ width: Int, _ height: Int, maxSide: Int = maxSide) -> (Int, Int) {
        guard width > 0, height > 0 else { return (width, height) }
        let longest = max(width, height)
        guard longest > maxSide else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Whether a picked file must be re-encoded as JPEG: HEIC/HEIF (not every viewer shows them), big
    /// JPEG or WebP photos, and any still image over `limit` bytes.
    static func needsReencode(mimeType: String, size: Int, limit: Int = Limits.attachmentBytes) -> Bool {
        let heic = mimeType == "image/heic" || mimeType == "image/heif"
        let big = (mimeType == "image/jpeg" || mimeType == "image/webp") && size > recompressAbove
        let tooLarge = mimeType.hasPrefix("image/") && mimeType != "image/gif" && size > limit
        return heic || big || tooLarge
    }

    /// `name` with its extension replaced by `ext`.
    static func withExtension(_ name: String, _ ext: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "\(name).\(ext)" }
        return "\(name[..<dot]).\(ext)"
    }

    /// Decodes `data`, applies its EXIF orientation, scales the longer side to at most `maxSide` and
    /// encodes JPEG at `jpegQuality`; nil when ImageIO cannot read it.
    static func jpeg(from data: Data, maxSide: Int = maxSide, quality: Double = jpegQuality) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let (tw, th) = fit(w, h, maxSide: maxSide)
        // The thumbnail API decodes at the target size and bakes the EXIF orientation in.
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(tw, th, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// A small decoded preview (for pending uploads), at most `maxPixel` on the longer side.
    static func thumbnail(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Turns picked bytes into an `UploadSource` the gateway accepts: HEIC/HEIF become JPEG, big photos are
/// scaled to 2048 px at quality 0.85, and anything still over the 10 MB limit is refused.
enum AttachmentPreparer {
    /// MIME type for a file: from its UTType, else its extension; `application/octet-stream` when unknown.
    static func mimeType(name: String, type: UTType?) -> String {
        if let m = type?.preferredMIMEType?.lowercased(), m != "application/octet-stream" {
            // UTType reports `image/heic` for HEIF sequences too; keep the gateway's spelling.
            return m == "image/heic-sequence" ? "image/heic" : (m == "image/heif-sequence" ? "image/heif" : m)
        }
        return mimeTypeForName(name) ?? "application/octet-stream"
    }

    /// Converts and checks `data`. Throws `HatangError` `file_too_large` or `unsupported_file_type`.
    static func prepare(_ data: Data, name: String, mimeType: String) throws -> UploadSource {
        if ImageScaling.needsReencode(mimeType: mimeType, size: data.count),
           let jpeg = ImageScaling.jpeg(from: data) {
            guard jpeg.count <= Limits.attachmentBytes else { throw tooLarge }
            return UploadSource(data: jpeg, name: ImageScaling.withExtension(name, "jpg"), mimeType: "image/jpeg")
        }
        // No decoder for it (or no need): send the original (the gateway accepts HEIC) if it fits.
        guard data.count <= Limits.attachmentBytes else { throw tooLarge }
        guard uploadMimeTypes.contains(mimeType) else {
            throw HatangError(code: "unsupported_file_type", message: "File type \(mimeType) is not allowed")
        }
        return UploadSource(data: data, name: name, mimeType: mimeType)
    }

    static var tooLarge: HatangError { HatangError(code: "file_too_large", message: "Files must be 10 MB or smaller") }
}

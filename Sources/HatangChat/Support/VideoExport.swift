import AVFoundation
import Foundation
import HatangChatCore

/// Compresses picked videos to an H.264 mp4 the gateway takes (≤ 25 MB) and makes still frames for the
/// tiles. AVFoundation only (no UIKit), so it builds on macOS too.
enum VideoExport {
    /// Export presets tried in order until the result fits: 720p first, then the smaller medium quality.
    static let presets = [AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality]

    /// Re-encodes the movie at `url` as mp4 (H.264, optimised for streaming) and returns its bytes. Tries
    /// each of `presets` until one fits `limit`; throws `video_too_large` when none does.
    static func mp4(from url: URL, limit: Int = Limits.videoBytes) async throws -> Data {
        let asset = AVURLAsset(url: url)
        var lastError: Error?
        var exported = false // some pass finished, just too big
        for preset in presets {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("hatang-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: out) }
            do {
                try await export(asset, preset: preset, to: out)
                let data = try Data(contentsOf: out) // not mapped: the file goes at the end of this pass
                if data.count <= limit { return data }
                exported = true
            } catch {
                lastError = error
            }
        }
        try Task.checkCancellation()
        if !exported, let lastError {
            throw HatangError(code: "read_failed", message: "Could not convert the video: \(lastError.localizedDescription)")
        }
        throw AttachmentPreparer.videoTooLarge
    }

    private static func export(_ asset: AVURLAsset, preset: String, to out: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw HatangError(code: "read_failed", message: "No exporter for \(preset)")
        }
        session.shouldOptimizeForNetworkUse = true
        if #available(iOS 18, macOS 15, *) {
            try await session.export(to: out, as: .mp4)
        } else {
            session.outputURL = out
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else {
                throw session.error ?? HatangError(code: "read_failed", message: "The video export did not finish")
            }
        }
    }

    /// A frame near the start of the movie at `url` (local or remote), at most `maxPixel` on the longer side.
    static func thumbnail(_ url: URL, maxPixel: Int) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        return try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
    }

    /// A frame of the movie in `data` (a pending upload), written to a temporary file for AVFoundation.
    static func thumbnail(_ data: Data, name: String, maxPixel: Int) async -> CGImage? {
        let ext = (name as NSString).pathExtension.isEmpty ? "mp4" : (name as NSString).pathExtension
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hatang-preview-\(UUID().uuidString).\(ext)")
        guard (try? data.write(to: file)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        return await thumbnail(file, maxPixel: maxPixel)
    }
}

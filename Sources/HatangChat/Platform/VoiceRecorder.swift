#if os(iOS)
import AVFoundation
import Foundation
import HatangChatCore
import Observation

/// Records a voice note with AVAudioRecorder: AAC in an `.m4a`, mono, 22.05 kHz at 48 kb/s (about 360 KB
/// a minute, so the 2-minute cap stays far below the 10 MB limit). The clip lives in a temporary file that
/// is deleted when the recording stops, sent or not.
@MainActor
@Observable
final class VoiceRecorder {
    /// How `start()` went.
    enum StartResult {
        case started
        /// The person refused the microphone (or it is restricted).
        case denied
        /// The audio session or the recorder could not start.
        case failed
    }

    /// When the current recording started; nil while idle.
    private(set) var startedAt: Date?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var file: URL?

    var isRecording: Bool { startedAt != nil }

    /// The recording settings: AAC, mono, 22.05 kHz, 48 kb/s.
    static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 22_050,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 48_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    /// Asks for the microphone (once; later calls answer from the saved choice) and starts recording.
    func start() async -> StartResult {
        if isRecording { return .started }
        guard await AVAudioApplication.requestRecordPermission() else { return .denied }
        if isRecording { return .started }
        let session = AVAudioSession.sharedInstance()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hatang-voice-\(UUID().uuidString).m4a")
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let r = try AVAudioRecorder(url: url, settings: Self.settings)
            if r.record() {
                recorder = r
                file = url
                startedAt = Date()
                return .started
            }
        } catch {}
        try? FileManager.default.removeItem(at: url)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        return .failed
    }

    /// Seconds recorded so far (0 while idle).
    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return now.timeIntervalSince(startedAt)
    }

    /// Stops recording and deletes the temporary file. With `keep`, returns the clip when it is long
    /// enough (`VoiceNote.minDuration`); nil when cancelled, too short or unreadable.
    @discardableResult
    func stop(keep: Bool) -> Data? {
        guard let r = recorder, let url = file else { return nil }
        let duration = r.currentTime > 0 ? r.currentTime : elapsed()
        r.stop()
        recorder = nil
        file = nil
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { try? FileManager.default.removeItem(at: url) }
        guard keep, VoiceNote.keeps(duration: duration), let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }
}
#endif

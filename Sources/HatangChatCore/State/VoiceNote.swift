import Foundation

/// Rules for voice notes, shared by the recorder and the bubbles (the same as the web widget): the mic
/// replaces Send while the text field is empty, a recording stops itself at 2 minutes and is sent, one under
/// 0.8 s is thrown away, and the clip goes out as an AAC `.m4a` named `voice-<ms>.m4a` with no text.
public enum VoiceNote {
    /// Longest recording; it is sent as is when it reaches this.
    public static let maxDuration: TimeInterval = 120
    /// Shorter recordings are discarded (a slip of the finger).
    public static let minDuration: TimeInterval = 0.8
    /// MIME type of the clips the SDK records (AAC in an MPEG-4 container).
    public static let mimeType = "audio/mp4"
    /// File name prefix that marks a recorded voice note (vs. an audio file picked from Files).
    public static let namePrefix = "voice-"

    /// `voice-<unix ms>.m4a`, like the widget's clips.
    public static func fileName(at date: Date = Date()) -> String {
        "\(namePrefix)\(Int64((date.timeIntervalSince1970 * 1000).rounded(.down))).m4a"
    }

    /// Whether the composer shows the mic instead of Send: the site allows voice notes (`voice_messages`),
    /// the composer is usable, nothing is staged and the text is empty (whitespace counts as empty).
    public static func showsMic(voiceMessages: Bool, text: String, hasStaged: Bool = false, enabled: Bool = true) -> Bool {
        voiceMessages && enabled && !hasStaged && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the host app may record: iOS kills an app that uses the microphone without
    /// `NSMicrophoneUsageDescription` in its Info.plist, so without the key the mic is hidden (voice notes still play).
    public static func appDeclaresMicrophone(_ info: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        guard let text = info?["NSMicrophoneUsageDescription"] as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a finished recording of `duration` seconds is long enough to send.
    public static func keeps(duration: TimeInterval) -> Bool { duration >= minDuration }

    /// Whether a recording of `duration` seconds has hit the cap and must stop (and be sent).
    public static func reachedLimit(_ duration: TimeInterval) -> Bool { duration >= maxDuration }

    /// `m:ss` for a recording or clip length (negative and non-finite values count as 0).
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let rest = s % 60
        return "\(s / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// Whether `name` is a recorded voice note (`voice-….m4a` / `.webm` / `.ogg`, any case).
    public static func isVoiceNoteName(_ name: String) -> Bool {
        name.lowercased().hasPrefix(namePrefix)
    }
}

/// Whether a file is audio: an `audio/` MIME type, or a generic type with an audio extension.
public func isAudioUpload(mimeType: String, name: String = "") -> Bool {
    if mimeType.lowercased().hasPrefix("audio/") { return true }
    if mimeType.lowercased().hasPrefix("video/") && !VoiceNote.isVoiceNoteName(name) { return false }
    let lower = name.lowercased()
    guard let dot = lower.lastIndex(of: ".") else { return false }
    let ext = lower[lower.index(after: dot)...]
    if ["m4a", "mp3", "aac", "ogg", "oga", "opus", "weba", "wav"].contains(String(ext)) { return true }
    // The widget's Chrome recordings are `voice-<ms>.webm` (stored as .m4a once the server converts them).
    return ext == "webm" && VoiceNote.isVoiceNoteName(lower)
}

extension Attachment {
    /// The attachment is audio (a voice note or an audio file), played in place.
    public var isAudio: Bool { isAudioUpload(mimeType: type, name: name) }

    /// The attachment is a recorded voice note (`voice-*` audio), labelled "Voice message".
    public var isVoiceNote: Bool { isAudio && VoiceNote.isVoiceNoteName(name) }
}

extension UploadSource {
    /// Audio (a voice note or an audio file).
    public var isAudio: Bool { isAudioUpload(mimeType: mimeType, name: name) }

    /// A recorded voice note (`voice-*` audio).
    public var isVoiceNote: Bool { isAudio && VoiceNote.isVoiceNoteName(name) }

    /// A recorded voice note ready for `ChatEngine.attach`: `voice-<ms>.m4a`, `audio/mp4`.
    public static func voiceNote(_ data: Data, at date: Date = Date()) -> UploadSource {
        UploadSource(data: data, name: VoiceNote.fileName(at: date), mimeType: VoiceNote.mimeType)
    }
}

#if os(iOS)
import AVFoundation
import HatangChatCore
import Observation
import SwiftUI

/// Plays one audio attachment at a time (AVPlayer streams the signed link): starting another clip stops
/// the one playing.
@MainActor
@Observable
final class AudioPlayback {
    static let shared = AudioPlayback()

    /// The attachment loaded in the player.
    private(set) var currentId: String?
    private(set) var isPlaying = false
    /// Seconds played of the current clip.
    private(set) var position: TimeInterval = 0
    /// Length of the current clip, once known.
    private(set) var duration: TimeInterval = 0
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    /// Plays `url` as `id`, or pauses / resumes it when it is the current clip.
    func toggle(id: String, url: URL) {
        if currentId == id, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                if duration > 0, position >= duration - 0.05 { player.seek(to: .zero); position = 0 }
                activateSession()
                player.play()
                isPlaying = true
            }
            return
        }
        stop()
        activateSession()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        currentId = id
        position = 0
        duration = 0
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
        p.play()
        isPlaying = true
    }

    /// Stops and unloads the current clip.
    func stop() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player?.pause()
        player = nil
        timeObserver = nil
        endObserver = nil
        currentId = nil
        isPlaying = false
        position = 0
        duration = 0
    }

    private func tick(_ seconds: Double) {
        if seconds.isFinite { position = seconds }
        if let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
    }

    private func finished() {
        isPlaying = false
        position = duration
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }
}

/// An audio attachment in a bubble: a play / pause button, a progress bar and the length; titled
/// "Voice message" for recorded notes, else the file name.
struct VoiceNoteView: View {
    let attachment: Attachment
    let foreground: Color
    let onExpired: (() -> Void)?
    @Environment(\.chat) private var chat
    @State private var length: TimeInterval?
    @State private var reported = false
    private var playback: AudioPlayback { .shared }

    var body: some View {
        let a = attachment
        let url = URL(string: a.url ?? "")
        let current = playback.currentId == a.id
        let playing = current && playback.isPlaying
        let total = current && playback.duration > 0 ? playback.duration : (length ?? 0)
        let progress = current && total > 0 ? min(playback.position / total, 1) : 0
        let title = a.isVoiceNote ? chat.strings.voiceNote : a.name
        HStack(spacing: Spacing.sm) {
            Button {
                if let url { playback.toggle(id: a.id, url: url) }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(foreground)
                    .frame(width: minTouch, height: minTouch)
                    .background(foreground.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(url == nil)
            .accessibilityLabel("\(title), \(total > 0 ? VoiceNote.clock(total) : fileSizeLabel(a.size))")
            .accessibilityValue(playing ? VoiceNote.clock(playback.position) : "")
            .accessibilityAddTraits(.startsMediaSession)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(foreground)
                Text(current && playback.position > 0 ? "\(VoiceNote.clock(playback.position)) / \(VoiceNote.clock(total))" : (total > 0 ? VoiceNote.clock(total) : "–:––"))
                    .font(.caption.monospacedDigit())
                    .opacity(0.75)
            }
            .foregroundStyle(foreground)
            .accessibilityHidden(true)
        }
        .frame(width: 220, alignment: .leading)
        .task(id: a.url) {
            guard let url, length == nil else { return }
            do {
                let d = try await AVURLAsset(url: url).load(.duration).seconds
                if d.isFinite, d > 0 { length = d }
            } catch {
                // The signed link expired: ask for fresh ones once.
                guard !reported else { return }
                reported = true
                onExpired?()
            }
        }
    }
}

/// The composer while a voice note records: cancel (delete), a pulsing red dot, the m:ss timer and
/// "Recording…"; the send button next to it stops and sends.
struct RecordingRow: View {
    let startedAt: Date
    let onCancel: () -> Void
    @Environment(\.chat) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        let t = chat.theme
        HStack(spacing: Spacing.sm) {
            Button(action: onCancel) {
                Image(systemName: "trash")
                    .font(.title3)
                    .foregroundStyle(t.palette.danger)
                    .frame(width: minTouch, height: minTouch)
            }
            .accessibilityLabel(chat.strings.dismiss)
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(dim ? 0.25 : 1)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { dim = true }
                    }
                TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
                    Text(VoiceNote.clock(context.date.timeIntervalSince(startedAt)))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(t.palette.fg)
                }
                Text(chat.strings.recording)
                    .font(.footnote)
                    .foregroundStyle(t.palette.muted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
        }
        .frame(minHeight: minTouch)
    }
}
#endif

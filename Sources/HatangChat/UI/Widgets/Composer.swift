#if os(iOS)
import HatangChatCore
import SwiftUI

/// The text field, the attach menu (photo library, files) and the send button. When the site allows voice
/// notes the send button is a mic while the field is empty; while recording, the field becomes the
/// recording row (cancel, timer) and the button sends the clip.
struct Composer: View {
    @Binding var text: String
    let enabled: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: (String) -> Void
    let onPickPhoto: () -> Void
    let onPickFile: () -> Void
    var voiceMessages = false
    /// When the voice note being recorded started; nil while not recording.
    var recordingSince: Date?
    var onRecord: () -> Void = {}
    /// Stops the recording: `true` sends it, `false` throws it away.
    var onStopRecording: (Bool) -> Void = { _ in }
    @Environment(\.chat) private var chat
    @ScaledMetric(relativeTo: .body) private var sendSize: CGFloat = 40

    var body: some View {
        let t = chat.theme
        let canSend = enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let recording = recordingSince != nil
        let showsMic = !recording && VoiceNote.showsMic(voiceMessages: voiceMessages, text: text, enabled: enabled)
        VStack(spacing: 0) {
            Divider().overlay(t.palette.border)
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                Menu {
                    Button(action: onPickPhoto) { Label(chat.strings.photoLibrary, systemImage: "photo.on.rectangle") }
                    Button(action: onPickFile) { Label(chat.strings.chooseFile, systemImage: "paperclip") }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundStyle(t.palette.muted)
                        .frame(minWidth: minTouch, minHeight: minTouch)
                }
                .disabled(!enabled || recording)
                .accessibilityLabel(chat.strings.attach)

                if let recordingSince {
                    RecordingRow(startedAt: recordingSince) { onStopRecording(false) }
                        .padding(.trailing, Spacing.xs)
                        .background(t.palette.raised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    TextField(chat.strings.placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.body)
                        .foregroundStyle(t.palette.fg)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.send)
                        .focused(focused)
                        .disabled(!enabled)
                        .onSubmit(send)
                        .onChange(of: text) { _, new in
                            if new.count > Limits.visitorText { text = String(new.prefix(Limits.visitorText)) }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm + 2)
                        .frame(minHeight: minTouch)
                        .background(t.palette.raised, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }

                if showsMic {
                    Button(action: onRecord) {
                        Image(systemName: "mic.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(t.onAccent)
                            .frame(width: max(sendSize, minTouch), height: max(sendSize, minTouch))
                            .background(t.accent, in: Circle())
                    }
                    .accessibilityLabel(chat.strings.recordVoice)
                } else if recording {
                    Button { onStopRecording(true) } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(t.onAccent)
                            .frame(width: max(sendSize, minTouch), height: max(sendSize, minTouch))
                            .background(t.accent, in: Circle())
                    }
                    .accessibilityLabel(chat.strings.send)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(canSend ? t.onAccent : t.palette.muted)
                            .frame(width: max(sendSize, minTouch), height: max(sendSize, minTouch))
                            .background(canSend ? t.accent : t.palette.raised, in: Circle())
                    }
                    .disabled(!canSend)
                    .accessibilityLabel(chat.strings.send)
                }
            }
            .padding(.leading, Spacing.xs)
            .padding(.trailing, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func send() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !v.isEmpty else { return }
        text = ""
        onSend(v)
    }
}
#endif

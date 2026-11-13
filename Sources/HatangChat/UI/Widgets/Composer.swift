#if os(iOS)
import HatangChatCore
import SwiftUI

/// Like the web widget (and Crisp): one rounded box with the text field on top and a tool row below —
/// the attach menu (photo library, files), the mic while the field is empty and voice notes are on, and
/// the send button. Its border takes the brand colour while typing or recording; while recording, the
/// field becomes the timer and the row holds delete and send.
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
    @ScaledMetric(relativeTo: .body) private var sendSize: CGFloat = 34

    var body: some View {
        let t = chat.theme
        let canSend = enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let recording = recordingSince != nil
        let showsMic = !recording && VoiceNote.showsMic(voiceMessages: voiceMessages, text: text, enabled: enabled)
        let active = recording || focused.wrappedValue
        let sendOn = canSend || recording
        let box = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let recordingSince {
                RecordingRow(startedAt: recordingSince)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xs)
                    .frame(minHeight: minTouch)
            } else {
                TextField(chat.strings.placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .foregroundStyle(t.palette.fg)
                    .tint(t.accent)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .focused(focused)
                    .disabled(!enabled)
                    .onSubmit(send)
                    .onChange(of: text) { _, new in
                        if new.count > Limits.visitorText { text = String(new.prefix(Limits.visitorText)) }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xs)
                    .frame(minHeight: minTouch)
            }
            HStack(spacing: 0) {
                if recording {
                    Button { onStopRecording(false) } label: {
                        tool("trash", color: t.palette.danger)
                    }
                    .accessibilityLabel(chat.strings.dismiss)
                } else {
                    Menu {
                        Button(action: onPickPhoto) { Label(chat.strings.photoLibrary, systemImage: "photo.on.rectangle") }
                        Button(action: onPickFile) { Label(chat.strings.chooseFile, systemImage: "paperclip") }
                    } label: {
                        tool("paperclip", color: t.palette.muted)
                    }
                    .disabled(!enabled)
                    .accessibilityLabel(chat.strings.attach)
                    if showsMic {
                        Button(action: onRecord) { tool("mic", color: t.palette.muted) }
                            .accessibilityLabel(chat.strings.recordVoice)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    if recording { onStopRecording(true) } else { send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sendOn ? t.onAccent : t.palette.dim)
                        .frame(width: sendSize, height: sendSize)
                        .background(sendOn ? t.accent : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(width: minTouch, height: minTouch)
                        .contentShape(Rectangle())
                }
                .disabled(!sendOn)
                .accessibilityLabel(chat.strings.send)
            }
            .padding(.horizontal, Spacing.xs)
        }
        .background(t.palette.bg, in: box)
        .overlay(box.strokeBorder(active ? t.accent : t.palette.border, lineWidth: active ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: active)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
    }

    private func tool(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19))
            .foregroundStyle(color)
            .frame(width: minTouch, height: minTouch)
            .contentShape(Rectangle())
    }

    private func send() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !v.isEmpty else { return }
        text = ""
        onSend(v)
    }
}
#endif

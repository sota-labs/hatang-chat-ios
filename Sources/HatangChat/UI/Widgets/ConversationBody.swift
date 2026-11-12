#if os(iOS)
import HatangChatCore
import PhotosUI
import SwiftUI

/// The conversation without a navigation bar: contact buttons, banners, away notice, message list (or the pre-chat form),
/// composer and branding line. Marks the conversation visible while on screen.
struct ConversationBody: View {
    let model: HatangChatModel
    @Environment(\.chat) private var chat
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var localError: String?
    @State private var pickingPhoto = false
    @State private var pickingFile = false
    @State private var photo: PhotosPickerItem?
    @State private var viewing: Viewed?
    @State private var recorder = VoiceRecorder()
    @FocusState private var composerFocused: Bool

    var body: some View {
        let state = model.state
        let t = chat.theme
        let away = state.online ? nil : state.config?.awayMessageFor(state.locale)
        let contacts = state.config?.contactButtons.filter(\.isOpenable) ?? []
        VStack(spacing: 0) {
            if !contacts.isEmpty {
                ContactButtonsRow(buttons: contacts)
            }
            ConnectionBanners(
                state: state,
                onReconnect: { model.run { await $0.connect() } },
                onDismissError: { model.fire { await $0.clearTransientError() } },
                localError: localError,
                onDismissLocal: { localError = nil }
            )
            if let away, !away.isEmpty {
                Text(away)
                    .font(.footnote)
                    .foregroundStyle(t.readable(t.palette.warn, on: t.palette.warnSoft))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.sm)
                    .background(t.palette.warnSoft)
            }
            if state.needsEmail {
                OfflineForm(
                    capture: state.config?.offlineCapture ?? .emailOptional,
                    draft: state.draft,
                    initialName: state.visitorName,
                    initialEmail: state.visitorEmail,
                    onSubmit: { name, email, message in
                        await model.engine?.submitOfflineForm(name: name, email: email, message: message)
                    },
                    onSkip: { model.run { await $0.skipEmail() } }
                )
                .frame(maxHeight: .infinity)
            } else {
                MessageList(
                    state: state,
                    onRetry: { id in model.run { await $0.retry(id) } },
                    onLoadEarlier: { model.run { await $0.loadEarlier() } },
                    onSubmitEmail: { email in await model.engine?.submitEmail(email) },
                    onAttachmentExpired: { m in model.run { await $0.refreshAttachments(m) } },
                    actions: actions
                )
                .frame(maxHeight: .infinity)
                VStack(spacing: 0) {
                    if state.conversation?.status == .closed {
                        ClosedBar { model.run { try await $0.openActive() } }
                    } else {
                        Composer(
                            text: $text,
                            enabled: state.phase != .outdated && state.phase != .failed,
                            focused: $composerFocused,
                            onSend: { v in model.run { await $0.send(v) } },
                            onPickPhoto: { pickingPhoto = true },
                            onPickFile: { pickingFile = true },
                            voiceMessages: state.config?.voiceMessages == true && VoiceNote.appDeclaresMicrophone(),
                            recordingSince: recorder.startedAt,
                            onRecord: startRecording,
                            onStopRecording: finishRecording
                        )
                    }
                    BrandingLine()
                }
                .background(t.palette.surface)
            }
        }
        .background(t.palette.bg)
        .environment(\.openImage, ImageViewerAction { viewing = Viewed(attachment: $0) })
        .onChange(of: text) { _, new in model.fire { await $0.onTextChanged(new) } }
        .onAppear {
            model.fire { await $0.setVisible(true) }
            model.engine?.emit(.opened)
        }
        .onDisappear {
            if recorder.isRecording { recorder.stop(keep: false) }
            if viewing == nil { AudioPlayback.shared.stop() }
            // The picture viewer covers the conversation without leaving it.
            guard viewing == nil, !pickingPhoto, !pickingFile else { return }
            model.fire { await $0.setVisible(false) }
            model.engine?.emit(.closed)
        }
        // The 2-minute cap: the note is sent as is (like the widget).
        .task(id: recorder.startedAt) {
            guard let started = recorder.startedAt else { return }
            try? await Task.sleep(for: .seconds(max(0, VoiceNote.maxDuration - Date().timeIntervalSince(started))))
            if recorder.startedAt == started { finishRecording(true) }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: AttachmentReader.pickerFilter)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            attach { try await AttachmentReader.read(item) }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: AttachmentReader.fileTypes) { result in
            if case .success(let url) = result { attach { try await AttachmentReader.read(url) } }
        }
        .fullScreenCover(item: $viewing) { v in
            Group {
                if v.attachment.isVideo {
                    VideoViewer(attachment: v.attachment) { viewing = nil }
                } else {
                    ImageViewer(attachment: v.attachment) { viewing = nil }
                }
            }
            .environment(\.chat, chat)
        }
    }

    private func startRecording() {
        let strings = chat.strings
        AudioPlayback.shared.stop()
        composerFocused = false
        Task {
            switch await recorder.start() {
            case .started: localError = nil
            case .denied: localError = strings.micDenied
            case .failed: localError = strings.errorGeneric
            }
        }
    }

    /// Stops the voice note; when `send`, uploads it like any file and sends it with no text.
    private func finishRecording(_ send: Bool) {
        guard let data = recorder.stop(keep: send) else { return }
        let source = UploadSource.voiceNote(data)
        model.run { await $0.attach(source) }
    }

    private func attach(_ read: @escaping @Sendable () async throws -> UploadSource) {
        let strings = chat.strings
        Task {
            do {
                let source = try await read()
                model.run { await $0.attach(source) }
            } catch {
                localError = errorText(error as? HatangError, strings: strings)
            }
        }
    }

    private var actions: CardActions {
        let commerce = model.commerce
        let strings = chat.strings
        return CardActions(
            onBuy: { product in
                if commerce.onBuyProduct?(product) != true {
                    text = "\(strings.wantBuy) \(product.name)"
                    composerFocused = true
                }
            },
            onPay: { payment in
                if commerce.onPay?(payment) != true, commerce.showExternalCheckout, let url = URL(string: payment.checkoutUrl) {
                    openURL(url)
                }
            },
            onReply: { label in model.run { await $0.send(label) } },
            onRate: { score, comment in model.fire { await $0.rate(score, comment: comment) } },
            externalCheckout: commerce.showExternalCheckout,
            hasPayHandler: commerce.onPay != nil
        )
    }
}

/// The picture or video on screen in the viewer.
private struct Viewed: Identifiable {
    let attachment: Attachment
    var id: String { attachment.id }
}
#endif

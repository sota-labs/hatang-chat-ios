#if os(iOS)
import HatangChatCore
import SwiftUI
import UIKit

/// Opens a picture in the full-screen viewer (set by the conversation).
struct ImageViewerAction: Sendable {
    var open: @MainActor @Sendable (Attachment) -> Void = { _ in }
}

private struct ImageViewerKey: EnvironmentKey {
    static let defaultValue = ImageViewerAction()
}

extension EnvironmentValues {
    var openImage: ImageViewerAction {
        get { self[ImageViewerKey.self] }
        set { self[ImageViewerKey.self] = newValue }
    }
}

extension Attachment {
    /// Shown as a thumbnail (HEIC is not rendered by every viewer; the gateway keeps it as a file).
    var showsInline: Bool {
        isImage && !(url ?? "").isEmpty && !type.contains("heic") && !type.contains("heif")
    }
}

/// One attachment of a sent or received message: a tappable thumbnail for pictures (opens the viewer), a
/// file row for everything else (opens it in the browser or Quick Look via the signed link).
struct AttachmentView: View {
    let attachment: Attachment
    let foreground: Color
    let onExpired: (() -> Void)?
    @Environment(\.chat) private var chat
    @Environment(\.openURL) private var openURL
    @Environment(\.openImage) private var openImage
    @ScaledMetric(relativeTo: .body) private var thumb: CGFloat = 220
    @State private var reported = false

    var body: some View {
        let a = attachment
        if a.showsInline, let url = URL(string: a.url ?? "") {
            Button {
                openImage.open(a)
            } label: {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        ZStack {
                            chat.theme.palette.raised
                            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(chat.theme.palette.dim)
                        }
                        .onAppear {
                            guard !reported else { return }
                            reported = true
                            onExpired?()
                        }
                    default:
                        chat.theme.palette.raised
                    }
                }
                .frame(width: min(thumb, 300), height: min(thumb, 300))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(a.name)
            .accessibilityHint(chat.strings.openFile)
            .accessibilityAddTraits(.isImage)
        } else {
            FileRow(
                symbol: symbolFor(a.type),
                name: a.name,
                detail: fileSizeLabel(a.size),
                foreground: foreground,
                label: "\(chat.strings.openFile): \(a.name), \(fileSizeLabel(a.size))",
                onTap: a.url.flatMap(URL.init(string:)).map { url in { openURL(url) } }
            )
        }
    }
}

/// The file of a message still uploading: a local preview for pictures, a file row otherwise, plus progress.
struct PendingAttachmentView: View {
    let upload: PendingUpload
    let foreground: Color
    @Environment(\.chat) private var chat
    @ScaledMetric(relativeTo: .body) private var thumb: CGFloat = 220
    @State private var preview: UIImage?

    var body: some View {
        let src = upload.source
        let size = min(thumb, 300)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if src.isImage && src.mimeType != "image/heic" && src.mimeType != "image/heif" {
                ZStack {
                    chat.theme.palette.raised
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .accessibilityLabel(src.name)
                .task(id: src) {
                    let data = src.data
                    preview = await Task.detached { ImageScaling.thumbnail(data, maxPixel: 600).map { UIImage(cgImage: $0) } }.value
                }
            } else {
                FileRow(symbol: symbolFor(src.mimeType), name: src.name, detail: fileSizeLabel(src.size), foreground: foreground, label: src.name, onTap: nil)
            }
            if !upload.done {
                Group {
                    if upload.progress > 0 {
                        ProgressView(value: upload.progress)
                    } else {
                        ProgressView(value: 0.05)
                    }
                }
                .progressViewStyle(.linear)
                .tint(foreground)
                .frame(width: src.isImage ? size : 180)
                .accessibilityLabel(chat.strings.uploading)
                .accessibilityValue("\(Int(upload.progress * 100))%")
            }
        }
    }
}

/// Icon, name and size of a file; opens it when tapped.
struct FileRow: View {
    let symbol: String
    let name: String
    let detail: String
    let foreground: Color
    let label: String
    let onTap: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(foreground)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption).opacity(0.75)
            }
            .foregroundStyle(foreground)
        }
        .frame(minHeight: minTouch)
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
    }
}

/// Full-screen picture: pinch to zoom, double-tap to zoom in and out, drag when zoomed, close to leave.
struct ImageViewer: View {
    let attachment: Attachment
    let onDismiss: () -> Void
    @Environment(\.chat) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: URL(string: attachment.url ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .scaleEffect(zoom)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .gesture(
                MagnifyGesture()
                    .onChanged { v in zoom = min(max(lastZoom * v.magnification, 1), 5) }
                    .onEnded { _ in
                        lastZoom = zoom
                        if zoom == 1 { reset() }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { v in
                            guard zoom > 1 else { return }
                            offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    if zoom > 1 { reset() } else { zoom = 2.5; lastZoom = 2.5 }
                }
            }
            .accessibilityLabel(attachment.name)
            .accessibilityAddTraits(.isImage)

            HStack {
                Text(attachment.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: minTouch, height: minTouch)
                }
                .accessibilityLabel(chat.strings.close)
            }
            .padding(.leading, Spacing.lg)
            .background(.black.opacity(0.5))
        }
        .environment(\.colorScheme, .dark)
    }

    private func reset() {
        zoom = 1
        lastZoom = 1
        offset = .zero
        lastOffset = .zero
    }
}
#endif

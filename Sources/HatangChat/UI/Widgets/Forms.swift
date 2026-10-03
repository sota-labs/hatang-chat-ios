#if os(iOS)
import HatangChatCore
import SwiftUI

/// Pre-chat form shown when nobody is online and the site wants an email before the first message.
struct OfflineForm: View {
    let capture: OfflineCapture
    let draft: String?
    let initialName: String?
    let initialEmail: String?
    let onSubmit: (_ name: String, _ email: String, _ message: String) async -> Void
    let onSkip: () -> Void
    @Environment(\.chat) private var chat
    @State private var name = ""
    @State private var email = ""
    @State private var message = ""
    @State private var busy = false
    @State private var error: String?
    @State private var seeded = false

    var body: some View {
        let t = chat.theme
        let s = chat.strings
        let hasDraft = !(draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(s.leaveEmail)
                    .font(.headline)
                    .foregroundStyle(t.palette.fg)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Spacing.xs)
                TextField(s.yourName, text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .chatField()
                TextField(s.yourEmail, text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(hasDraft ? .done : .next)
                    .onSubmit { if hasDraft { submit(hasDraft) } }
                    .chatField()
                if !hasDraft {
                    TextField(s.placeholder, text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .chatField()
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(t.readable(t.palette.danger, on: t.palette.bg))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button { submit(hasDraft) } label: { Text(s.start) }
                    .buttonStyle(ChatButtonStyle(fullWidth: true))
                    .disabled(busy)
                    .padding(.top, Spacing.sm)
                if capture == .emailOptional {
                    Button(s.skip, action: onSkip)
                        .font(.body)
                        .foregroundStyle(t.palette.muted)
                        .frame(maxWidth: .infinity, minHeight: minTouch)
                        .disabled(busy)
                }
            }
            .padding(Spacing.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            name = initialName ?? ""
            email = initialEmail ?? ""
        }
    }

    private func submit(_ hasDraft: Bool) {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = (hasDraft ? draft ?? "" : message).trimmingCharacters(in: .whitespacesAndNewlines)
        if capture == .emailRequired && (e.isEmpty || !e.contains("@")) {
            error = chat.strings.yourEmail
            announce(chat.strings.yourEmail)
            return
        }
        if m.isEmpty {
            error = chat.strings.placeholder
            announce(chat.strings.placeholder)
            return
        }
        busy = true
        error = nil
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await onSubmit(n, e, m)
            busy = false
        }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// Inline email field under an assistant message that asked for one.
struct EmailRequestForm: View {
    let onSubmit: (String) async -> Void
    @Environment(\.chat) private var chat
    @State private var email = ""
    @State private var busy = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TextField(chat.strings.yourEmail, text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(submit)
                .chatField()
            Button(chat.strings.sendEmail, action: submit)
                .buttonStyle(ChatButtonStyle())
                .disabled(busy)
        }
        .padding(.top, Spacing.xs)
    }

    private func submit() {
        let v = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, v.contains("@"), !busy else { return }
        busy = true
        Task {
            await onSubmit(v)
            busy = false
        }
    }
}
#endif

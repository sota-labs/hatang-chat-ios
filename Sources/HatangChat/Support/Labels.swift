import Foundation
import HatangChatCore

/// "2.4 MB", "830 KB", "12 B".
func fileSizeLabel(_ bytes: Int) -> String {
    if bytes >= 1024 * 1024 { return String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / (1024 * 1024)) }
    if bytes >= 1024 { return "\(Int((Double(bytes) / 1024).rounded())) KB" }
    return "\(bytes) B"
}

/// User-facing text for an engine or picker error.
func errorText(_ e: HatangError?, strings: HatangChatStrings) -> String {
    guard let e else { return strings.errorGeneric }
    if e.isRateLimit { return strings.rateLimited }
    switch e.code {
    case "file_too_large": return strings.tooLarge
    case "unsupported_file_type": return strings.unsupportedFile
    case "timeout", "closed": return strings.sendFailed
    case "network_error", "read_failed": return strings.errorGeneric
    default: return e.message.isEmpty ? strings.errorGeneric : e.message
    }
}

/// What an inbox row shows for one conversation.
struct InboxRowModel: Hashable, Sendable {
    var title: String
    var initial: String
    var preview: String
    var time: String
    var finished: Bool
    var unread: Int
    var avatarURL: String?

    /// VoiceOver label: title, preview, time, status, unread count.
    func accessibilityLabel(strings: HatangChatStrings, locale: HatangLocale) -> String {
        [
            title,
            preview.isEmpty ? nil : preview,
            time.isEmpty ? nil : time,
            finished ? strings.resolved : nil,
            unread > 0 ? strings.unread(unread, locale: locale) : nil,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Builds an inbox row: who answered (else the site, else "Support"), the last message with a "You: "
/// prefix for the visitor's own, the time today or the day label, the resolved flag and unread count.
func inboxRow(
    _ c: VisitorConversationDto,
    siteName: String,
    strings: HatangChatStrings,
    locale: HatangLocale,
    now: Date = Date(),
    timeZone: TimeZone = .current
) -> InboxRowModel {
    let agent = c.agent?.name ?? ""
    let title = !agent.isEmpty ? agent : (!siteName.isEmpty ? siteName : strings.team)
    let at = c.lastMessageAt ?? c.updatedAt ?? c.createdAt
    var time = ""
    if let at {
        time = dayOf(at, timeZone: timeZone) == dayOf(now, timeZone: timeZone)
            ? timeOf(at, timeZone: timeZone)
            : dayLabel(at, locale: locale, strings: strings, now: now, timeZone: timeZone)
    }
    let text = previewOf(c.lastMessagePreview ?? "")
    let mine = c.lastMessageSenderType == .visitor
    return InboxRowModel(
        title: title,
        initial: title.first.map { String($0).uppercased() } ?? "?",
        preview: mine && !text.isEmpty ? "\(strings.you): \(text)" : text,
        time: time,
        finished: c.status == .resolved || c.status == .closed,
        unread: c.visitorUnread,
        avatarURL: c.agent?.avatarUrl
    )
}

/// Badge text: the count, capped at "99+".
func badgeText(_ n: Int) -> String { n > 99 ? "99+" : "\(n)" }

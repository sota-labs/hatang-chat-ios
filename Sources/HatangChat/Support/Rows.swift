import Foundation
import HatangChatCore

/// A message bubble row.
struct MessageRow: Hashable, Sendable {
    var message: MessageDto
    var mine: Bool
    /// "Seen" under the last own message the team read.
    var showSeen: Bool
    /// Sender name for the team's messages (with the AI label for the bot).
    var senderLabel: String?
    /// Show the inline email field (the bot asked and no email is known).
    var askEmail: Bool = false
    /// The card under the message.
    var card: MessageCard?
}

/// One row of the message list, in display order (oldest first).
enum ChatRow: Hashable, Sendable, Identifiable {
    /// "Today" / "Yesterday" / a date.
    case day(label: String, day: CalendarDay)
    /// The site greeting while the conversation is empty, signed by an online agent when the site asks.
    case greeting(String, sender: String?)
    /// A message bubble.
    case message(MessageRow)
    /// A system line (notice, handoff, rated).
    case system(id: String, text: String)
    /// An outgoing message without an ack.
    case pending(PendingMessage)
    /// The agent is typing (empty name when unnamed).
    case typing(String)

    /// Stable key for the list.
    var id: String {
        switch self {
        case .day(_, let d): return "day-\(d.year)-\(d.month)-\(d.day)"
        case .greeting: return "greeting"
        case .message(let m): return "m-\(m.message.id)"
        case .system(let id, _): return "s-\(id)"
        case .pending(let p): return "p-\(p.clientId)"
        case .typing: return "typing"
        }
    }
}

/// Rows for `state`: day separators, the greeting when empty, notice / handoff / rated events only, "Seen"
/// under the last read own message, sender names for the team, cards (quick replies only on the newest
/// item), pending bubbles and the typing indicator. Port of the Android and Flutter `buildRows`.
func buildRows(_ state: ChatState, strings: HatangChatStrings, now: Date = Date(), timeZone: TimeZone = .current) -> [ChatRow] {
    var rows: [ChatRow] = []
    let locale = state.locale
    let items = state.timeline.items
    if items.isEmpty, let row = greetingRow(state.config, online: state.online, locale: locale) { rows.append(row) }
    var lastVisitorRead = 0
    for case .message(let m) in items where m.isMine && m.readAt != nil && m.seq > lastVisitorRead {
        lastVisitorRead = m.seq
    }
    var lastDay: CalendarDay?
    let newestId = items.last?.id
    // Payment cards are not rewritten live when the customer pays; the `order_paid` rows say so.
    let paid = PaidPayments(items)
    for item in items {
        let day = dayOf(item.createdAt, timeZone: timeZone)
        if lastDay != day {
            lastDay = day
            rows.append(.day(label: dayLabel(item.createdAt, locale: locale, strings: strings, now: now, timeZone: timeZone), day: day))
        }
        switch item {
        case .event(let e):
            switch e.type {
            case "notice":
                let text: String
                if let key = e.data["key"]?.stringValue {
                    text = strings.t(key, locale: locale)
                } else {
                    text = e.data["text"]?.stringValue ?? ""
                }
                if !text.isEmpty { rows.append(.system(id: e.id, text: text)) }
            case "handoff": rows.append(.system(id: e.id, text: strings.transferredToAgent))
            case "rated": rows.append(.system(id: e.id, text: strings.rateThanks))
            default: break
            }
        case .message(let m):
            let mine = m.isMine
            var label: String?
            if !mine {
                if let name = m.senderName, !name.isEmpty {
                    label = m.senderType == .bot ? "\(name) · \(strings.aiLabel)" : name
                } else if m.senderType == .bot {
                    label = strings.aiLabel
                }
            }
            var card = mine ? nil : paid.resolve(cardOf(m.metadata))
            if case .quickReplies = card, m.id != newestId { card = nil }
            let askEmail = !mine && m.metadata?["kind"]?.stringValue == "email_request" && (state.visitorEmail ?? "").isEmpty
            // A card the SDK draws replaces the plain-text copy the gateway stores for other channels.
            var shown = m
            if card != nil { shown.content = cardBubbleText(m.content, card: card, intro: m.metadata?["intro"]?.stringValue) }
            rows.append(.message(MessageRow(
                message: shown,
                mine: mine,
                showSeen: mine && lastVisitorRead == m.seq,
                senderLabel: label,
                askEmail: askEmail,
                card: card
            )))
        }
    }
    for p in state.pending { rows.append(.pending(p)) }
    if let t = state.typingAgent { rows.append(.typing(t)) }
    return rows
}

/// The greeting row for an empty conversation: nil when the site has none or turned it off for phones,
/// signed by the first online agent when the site asks for it.
func greetingRow(_ config: SiteConfig?, online: Bool, locale: HatangLocale) -> ChatRow? {
    guard let config, config.showsGreetingInApp, let g = config.greetingFor(locale), !g.isEmpty else { return nil }
    return .greeting(g, sender: config.greetingSigner(online: online))
}

/// The newest message from the team worth announcing to VoiceOver: not local, not older than two minutes.
func announcement(for m: MessageDto, strings: HatangChatStrings, now: Date = Date()) -> String? {
    guard !m.isMine, !m.id.hasPrefix("local-"), abs(now.timeIntervalSince(m.createdAt)) <= 120 else { return nil }
    let who = (m.senderName?.isEmpty == false ? m.senderName : nil) ?? strings.team
    var text = plainTextOf(formatMessage(m.content))
    if text.isEmpty { text = m.attachments.map(\.name).joined(separator: ", ") }
    return "\(who): \(text)"
}

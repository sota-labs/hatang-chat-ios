import Foundation

/// One piece of a formatted message (port of `format.ts`). Never HTML.
public enum FormatToken: Sendable, Hashable {
    /// Plain text.
    case text(String)
    /// A line break.
    case br
    /// A link.
    case link(href: String, label: String)
    /// Bold text.
    case bold(String)
    /// Italic text.
    case italic(String)
    /// Inline code.
    case code(String)
}

private enum Patterns {
    // NSRegularExpression is Sendable (immutable once built).
    static let url = try! NSRegularExpression(pattern: #"\bhttps?://[^\s<>()"']+[^\s<>()"'.,;:!?]"#)
    static let inline = try! NSRegularExpression(pattern: #"(\*\*[^*\n]+\*\*|_[^_\n]+_|`[^`\n]+`)"#)
}

private struct Part {
    let value: String
    let match: Bool
}

private func splitBy(_ s: String, _ re: NSRegularExpression) -> [Part] {
    let ns = s as NSString
    var parts: [Part] = []
    var last = 0
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        if m.range.location > last {
            parts.append(Part(value: ns.substring(with: NSRange(location: last, length: m.range.location - last)), match: false))
        }
        parts.append(Part(value: ns.substring(with: m.range), match: true))
        last = m.range.location + m.range.length
    }
    if last < ns.length { parts.append(Part(value: ns.substring(from: last), match: false)) }
    return parts
}

/// Tokenises `text`: links, `**bold**`, `_italic_`, `` `code` `` and line breaks. HTML is never interpreted.
public func formatMessage(_ text: String) -> [FormatToken] {
    var out: [FormatToken] = []
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.components(separatedBy: "\n")
    for (i, line) in lines.enumerated() {
        if i > 0 { out.append(.br) }
        for seg in splitBy(line, Patterns.url) {
            if seg.match {
                out.append(.link(href: seg.value, label: seg.value))
                continue
            }
            for inl in splitBy(seg.value, Patterns.inline) {
                guard inl.match else {
                    if !inl.value.isEmpty { out.append(.text(inl.value)) }
                    continue
                }
                let v = inl.value
                if v.hasPrefix("**") {
                    out.append(.bold(String(v.dropFirst(2).dropLast(2))))
                } else if v.hasPrefix("`") {
                    out.append(.code(String(v.dropFirst().dropLast())))
                } else {
                    out.append(.italic(String(v.dropFirst().dropLast())))
                }
            }
        }
    }
    return out
}

/// Plain-text preview (one line, trimmed, at most `max` characters).
public func previewOf(_ text: String, max: Int = 200) -> String {
    let one = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return one.count > max ? String(one.prefix(max - 1)) + "…" : one
}

/// The plain text of `tokens` (labels for links, no markers).
public func plainTextOf(_ tokens: [FormatToken]) -> String {
    var s = ""
    for t in tokens {
        switch t {
        case .text(let v), .bold(let v), .italic(let v), .code(let v): s += v
        case .link(_, let label): s += label
        case .br: s += "\n"
        }
    }
    return s
}

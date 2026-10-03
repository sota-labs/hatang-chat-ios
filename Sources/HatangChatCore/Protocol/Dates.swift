import Foundation

// ISO-8601 timestamps as the gateway writes them (`2026-09-27T10:01:00.000Z`). Formatters are only read
// after creation, which Foundation documents as thread-safe.

nonisolated(unsafe) private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func localFormatter(_ pattern: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = .current
    f.dateFormat = pattern
    return f
}

/// ISO-8601 with an offset, or a local date-time (read in the device zone, like the Dart SDK). Nil when
/// unparseable.
func parseISODate(_ s: String) -> Date? {
    if let d = isoFractional.date(from: s) { return d }
    if let d = isoPlain.date(from: s) { return d }
    // More than millisecond precision: cut the fraction to three digits and try again.
    if let dot = s.firstIndex(of: "."), let end = s[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) {
        let digits = s[s.index(after: dot)..<end]
        if digits.count > 3 {
            let cut = String(s[..<s.index(after: dot)]) + digits.prefix(3) + s[end...]
            if let d = isoFractional.date(from: cut) { return d }
        }
    }
    for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
        if let d = localFormatter(pattern).date(from: s) { return d }
    }
    return nil
}

/// `2026-09-27T10:01:00.000Z`, the shape the gateway uses.
func formatISODate(_ d: Date) -> String {
    isoFractional.string(from: d)
}

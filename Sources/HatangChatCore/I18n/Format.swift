import Foundation

/// A calendar date (no time, no zone).
public struct CalendarDay: Sendable, Hashable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

private func calendar(_ zone: TimeZone) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c
}

/// `HH:mm` in `timeZone` (both locales use 24-hour clocks here).
public func timeOf(_ at: Date, timeZone: TimeZone = .current) -> String {
    let c = calendar(timeZone).dateComponents([.hour, .minute], from: at)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

/// Calendar date only, in `timeZone`.
public func dayOf(_ at: Date, timeZone: TimeZone = .current) -> CalendarDay {
    let c = calendar(timeZone).dateComponents([.year, .month, .day], from: at)
    return CalendarDay(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
}

/// `d/M/yyyy` for Vietnamese, `M/d/yyyy` for English.
public func dateOf(_ at: Date, locale: HatangLocale, timeZone: TimeZone = .current) -> String {
    let d = dayOf(at, timeZone: timeZone)
    return locale == .vi ? "\(d.day)/\(d.month)/\(d.year)" : "\(d.month)/\(d.day)/\(d.year)"
}

/// "Today", "Yesterday" or the date, for a day separator.
public func dayLabel(_ at: Date, locale: HatangLocale, strings: HatangChatStrings, now: Date = Date(), timeZone: TimeZone = .current) -> String {
    let cal = calendar(timeZone)
    let day = dayOf(at, timeZone: timeZone)
    let today = dayOf(now, timeZone: timeZone)
    if day == today { return strings.today }
    if let y = cal.date(byAdding: .day, value: -1, to: now), dayOf(y, timeZone: timeZone) == day { return strings.yesterday }
    return dateOf(at, locale: locale, timeZone: timeZone)
}

private let weekdaysVi = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
private let weekdaysEn = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

/// Short weekday name (`weekday` 1 = Monday … 7 = Sunday, ISO order).
public func weekdayShort(_ weekday: Int, locale: HatangLocale) -> String {
    (locale == .vi ? weekdaysVi : weekdaysEn)[min(max(weekday - 1, 0), 6)]
}

/// "Back at Mon 09:00" / "Quay lại lúc T2 09:00".
public func backAtLabel(_ nextOpenAt: Date, locale: HatangLocale, strings: HatangChatStrings, timeZone: TimeZone = .current) -> String {
    // Calendar weekdays are 1 = Sunday … 7 = Saturday; convert to ISO.
    let w = calendar(timeZone).component(.weekday, from: nextOpenAt)
    let iso = w == 1 ? 7 : w - 1
    return "\(strings.backAt) \(weekdayShort(iso, locale: locale)) \(timeOf(nextOpenAt, timeZone: timeZone))"
}

/// Header subtitle: online, or offline with the next opening time.
public func availabilityLabel(_ av: Availability, locale: HatangLocale, strings: HatangChatStrings, timeZone: TimeZone = .current) -> String {
    if av.online { return strings.online }
    guard let next = av.nextOpenAt else { return strings.offline }
    return "\(strings.offline) · \(backAtLabel(next, locale: locale, strings: strings, timeZone: timeZone))"
}

/// Groups digits with fixed-locale formatters: `1.234.567` (vi_VN) or `1,234,567` (en_US); exactly
/// `decimals` fraction digits, rounded half up.
public func formatNumber(_ value: Double, locale: HatangLocale, decimals: Int = 0) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: locale == .vi ? "vi_VN" : "en_US")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = true
    f.groupingSize = 3
    f.groupingSeparator = locale == .vi ? "." : ","
    f.decimalSeparator = locale == .vi ? "," : "."
    f.minusSign = "-"
    f.minimumFractionDigits = decimals
    f.maximumFractionDigits = decimals
    f.roundingMode = .halfUp
    var out = f.string(from: NSNumber(value: value)) ?? String(value)
    // `-0` after rounding reads as zero.
    if out.hasPrefix("-"), !out.contains(where: { ("1"..."9").contains($0) }) { out.removeFirst() }
    return out
}

/// Vietnamese đồng: `1.234.567 ₫` (rounded to whole đồng).
public func vnd(_ value: Double, locale: HatangLocale = .vi) -> String {
    "\(formatNumber(value, locale: locale)) ₫"
}

/// Money in `currency`: đồng gets `vnd`, everything else `1,234.56 USD`.
public func money(_ value: Double, currency: String, locale: HatangLocale) -> String {
    if currency.uppercased() == "VND" { return vnd(value, locale: locale) }
    return "\(formatNumber(value, locale: locale, decimals: 2)) \(currency.uppercased())"
}

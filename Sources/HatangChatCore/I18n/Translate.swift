import Foundation

private let paramRe = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)

private func text(of value: any Sendable) -> String {
    if let d = value as? Double, d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
    return "\(value)"
}

/// Replaces `{name}` placeholders in `template` with `params`; unknown names stay as written.
public func interpolate(_ template: String, _ params: [String: any Sendable]? = nil) -> String {
    guard let params, !params.isEmpty else { return template }
    let ns = template as NSString
    var out = ""
    var last = 0
    for m in paramRe.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        let key = ns.substring(with: m.range(at: 1))
        if let v = params[key] {
            out += text(of: v)
        } else {
            out += ns.substring(with: m.range)
        }
        last = m.range.location + m.range.length
    }
    out += ns.substring(from: last)
    return out
}

/// CLDR cardinal category for the two locales; Vietnamese has no plural forms.
public func pluralCategory(_ locale: HatangLocale, _ n: Double) -> String {
    locale == .en && n == 1 ? "one" : "other"
}

private func numeric(_ v: (any Sendable)?) -> Double? {
    switch v {
    case let i as Int: return Double(i)
    case let d as Double: return d
    case let f as Float: return Double(f)
    case let i as Int64: return Double(i)
    case let i as Int32: return Double(i)
    default: return nil
    }
}

/// Looks up `key` in `dict`: with a numeric `count` param the `key_one` / `key_other` variant is tried
/// first, then the bare key, then `fallback`, then the key itself.
public func translate(
    _ dict: [String: String],
    locale: HatangLocale,
    key: String,
    params: [String: any Sendable]? = nil,
    fallback: [String: String]? = nil
) -> String {
    var text: String?
    if let count = numeric(params?["count"]) {
        let variant = "\(key)_\(pluralCategory(locale, count))"
        text = dict[variant] ?? fallback?[variant]
    }
    return interpolate(text ?? dict[key] ?? fallback?[key] ?? key, params)
}

/// Locale resolution (same rule as the web widget and the agent app): explicit `preferred` → site default
/// unless `auto` → a device language starting with `en` → English, everything else Vietnamese.
public func pickLocale(preferred: String? = nil, siteDefault: String = "auto", deviceLanguage: String? = nil) -> HatangLocale {
    if let l = HatangLocale.tryParse(preferred) { return l }
    if let l = HatangLocale.tryParse(siteDefault) { return l }
    return (deviceLanguage ?? "").lowercased().hasPrefix("en") ? .en : .vi
}

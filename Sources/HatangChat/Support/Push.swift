import Foundation
import HatangChatCore

/// Helpers for push payloads sent by the Hatang gateway. The SDK has no Firebase or UserNotifications
/// dependency: the host receives the notification and hands its `userInfo` to
/// `HatangChat.isHatangNotification` / `HatangChat.handleNotification`.
enum HatangPush {
    /// `userInfo` flattened to strings: the top level, or a map nested under `data` (as a dictionary or a
    /// JSON string, which some relays use) when the top level has no `hatang` key.
    static func payload(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        let top = flatten(userInfo)
        if top["hatang"] != nil { return top }
        let nested: [String: String]?
        switch userInfo["data"] {
        case let d as [AnyHashable: Any]: nested = flatten(d)
        case let s as String: nested = (try? JSONSerialization.jsonObject(with: Data(s.utf8))).flatMap { $0 as? [String: Any] }.map(flatten)
        default: nested = nil
        }
        guard let inner = nested, inner["hatang"] != nil else { return top }
        return top.merging(inner) { _, new in new }
    }

    /// `true` when the payload came from Hatang (`hatang: "1"`, `1` or `true`).
    static func isHatang(_ userInfo: [AnyHashable: Any]) -> Bool {
        let v = payload(userInfo)["hatang"]?.trimmingCharacters(in: .whitespaces).lowercased()
        return v == "1" || v == "true"
    }

    /// The conversation the notification points at, if any.
    static func conversationId(_ userInfo: [AnyHashable: Any]) -> String? {
        let p = payload(userInfo)
        guard let v = p["conversation_id"] ?? p["conversationId"], !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    private static func flatten(_ d: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in d {
            guard let key = k.base as? String else { continue }
            switch v {
            case let s as String: out[key] = s
            case let n as NSNumber:
                // JSON booleans arrive as NSNumber too.
                out[key] = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
            default: break
            }
        }
        return out
    }
}

/// The restore token inside a "we replied" magic link: a `hatang_restore` query parameter, or the segment
/// after `c` in the path (`…/c/<token>`, at least 10 characters); nil otherwise.
func linkTokenFrom(_ url: URL) -> String? {
    let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if let q = c?.queryItems?.first(where: { $0.name == "hatang_restore" })?.value, !q.isEmpty { return q }
    return linkTokenFromSegments(url.path.split(separator: "/").map(String.init))
}

/// The token after a `c` segment, at least 10 characters.
func linkTokenFromSegments(_ segments: [String]) -> String? {
    let segs = segments.filter { !$0.isEmpty }
    guard let i = segs.firstIndex(of: "c"), i + 1 < segs.count, segs[i + 1].count >= 10 else { return nil }
    return segs[i + 1]
}

/// Lower-case hex of an APNs device token.
func hexToken(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

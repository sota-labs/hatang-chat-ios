import CryptoKit
import Foundation

/// The app account token to pass when starting a store purchase (`Product.PurchaseOption.appAccountToken`), so
/// App Store Server Notifications reach the right customer in Hatang. A UUID v5 of your user id within the site:
/// the same value the server and the other SDKs compute.
public enum PurchaseToken {
    private static let urlNamespace = UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8")!

    /// RFC 4122 UUID version 5 (SHA-1, name-based).
    public static func uuidv5(_ name: String, namespace: UUID) -> UUID {
        var ns = namespace.uuid
        var data = withUnsafeBytes(of: &ns) { Data($0) }
        data.append(Data(name.utf8))
        var h = Array(Insecure.SHA1.hash(data: data)).prefix(16).map { $0 }
        h[6] = (h[6] & 0x0F) | 0x50
        h[8] = (h[8] & 0x3F) | 0x80
        return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
    }

    /// The token for one of your users on a site.
    public static func make(siteId: String, userId: String) -> UUID {
        uuidv5(userId, namespace: uuidv5("hatang:site:\(siteId)", namespace: urlNamespace))
    }
}

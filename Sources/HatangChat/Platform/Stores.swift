#if os(iOS)
import Foundation
import HatangChatCore
import Security

/// Secure storage for the visitor token: generic passwords in the Keychain under service
/// `dev.hatang.chat`, readable after the first unlock (so a push can wake the app and reconnect). Keychain
/// errors are logged and read as "nothing stored": the SDK then bootstraps a fresh visitor.
public final class KeychainStore: KeyValueStore, Sendable {
    /// The Keychain service name.
    public let service: String
    private let logger: HatangLogger

    public init(service: String = "dev.hatang.chat", logger: HatangLogger = .silent) {
        self.service = service
        self.logger = logger
    }

    private func query(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    public func get(_ key: String) async throws -> String? {
        var q = query(key)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else {
            logger.warn("keychain read failed: \(status)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String, _ value: String) async throws {
        let data = Data(value.utf8)
        let update: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(query(key) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add.merge(update) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess { logger.warn("keychain write failed: \(status)") }
    }

    public func remove(_ key: String) async throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { logger.warn("keychain delete failed: \(status)") }
    }

    /// Deletes every item of this service (Keychain items outlive an uninstall; the SDK wipes them on the
    /// first launch after a reinstall).
    public func removeAll() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
    }
}

/// Plain preferences in `UserDefaults` (conversation id, last seq, locale, install id, push token).
public final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func get(_ key: String) async throws -> String? { defaults.string(forKey: key) }

    public func set(_ key: String, _ value: String) async throws { defaults.set(value, forKey: key) }

    public func remove(_ key: String) async throws { defaults.removeObject(forKey: key) }
}
#endif

import Foundation

/// A tiny async key/value store. The iOS layer provides one backed by the Keychain (the token) and one by
/// `UserDefaults`.
public protocol KeyValueStore: Sendable {
    /// Reads `key`, or nil when absent.
    func get(_ key: String) async throws -> String?
    /// Writes `value` under `key`.
    func set(_ key: String, _ value: String) async throws
    /// Removes `key`.
    func remove(_ key: String) async throws
}

/// In-memory store for tests and for hosts that opt out of persistence.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let map: Locked<[String: String]>

    public init(_ initial: [String: String] = [:]) {
        map = Locked(initial)
    }

    /// A snapshot of the current contents.
    public var values: [String: String] { map.current }

    public func get(_ key: String) async throws -> String? { map.withLock { $0[key] } }

    public func set(_ key: String, _ value: String) async throws { map.withLock { $0[key] = value } }

    public func remove(_ key: String) async throws { _ = map.withLock { $0.removeValue(forKey: key) } }
}

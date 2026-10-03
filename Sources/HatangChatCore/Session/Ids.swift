import Foundation

/// Key under which the install id lives (not site-scoped: one per install).
public let installIdKey = "hatang_chat.install_id"

private let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

private func random(_ n: Int) -> String {
    String((0..<n).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
}

/// Optimistic message id, matched against the server's ack and echo.
func newClientId(_ now: Date) -> String {
    "\(String(now.epochMillis, radix: 36))-\(random(5))"
}

/// One id per app install, minted once and kept in `store`; the gateway budgets bootstraps and upserts
/// devices by it. Always at least 8 characters.
func loadInstallId(_ store: any KeyValueStore, now: Date) async -> String {
    if let existing = try? await store.get(installIdKey), existing.count >= 8 { return existing }
    let id = "ins_\(String(now.epochMillis, radix: 36))\(random(12))"
    try? await store.set(installIdKey, id)
    return id
}

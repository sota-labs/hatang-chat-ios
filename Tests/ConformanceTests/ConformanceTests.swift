import Foundation
import HatangChatCore
import XCTest

/// The SDK conformance suite (sdks/conformance) against a live gateway, one test per scenario (`testC01`
/// … `testC12`). Configured from the environment:
///
/// ```
/// HATANG_CHAT_URL=http://localhost:3002 HATANG_SITE_ID=… HATANG_APP_KEY=… HATANG_IDENTITY_SECRET=… \
/// HATANG_AGENT_TOKEN=… swift test --filter ConformanceTests
/// ```
///
/// `HATANG_FIXTURES` points at the scenario directory (default: `../conformance/scenarios` next to this
/// package). Without the variables every scenario is skipped with the reason.
final class ConformanceTests: XCTestCase {
    private static let env = ProcessInfo.processInfo.environment

    private static let scenarioDir: URL = {
        if let dir = env["HATANG_FIXTURES"], !dir.isEmpty { return URL(fileURLWithPath: dir) }
        // Tests/ConformanceTests/ConformanceTests.swift → sdks/conformance/scenarios
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conformance/scenarios")
    }()

    private static let scenarios: Result<[Scenario], any Error> = Result { try loadScenarios(scenarioDir) }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    /// Why `s` cannot run here, or nil.
    private func skipReason(_ s: Scenario) -> String? {
        let env = Self.env
        let missing = ["HATANG_CHAT_URL", "HATANG_SITE_ID", "HATANG_APP_KEY"].filter { (env[$0] ?? "").isEmpty }
        if !missing.isEmpty {
            return "\(missing.joined(separator: ", ")) not set: run against a gateway with the output of `just seed-chat-site --json`"
        }
        if s.source.contains("{agent_token}"), (env["HATANG_AGENT_TOKEN"] ?? "").isEmpty {
            return "HATANG_AGENT_TOKEN is not set (\(s.id) drives the agent side)"
        }
        if s.source.contains("{hmac:"), (env["HATANG_IDENTITY_SECRET"] ?? "").isEmpty {
            return "HATANG_IDENTITY_SECRET is not set (\(s.id) signs identities)"
        }
        return nil
    }

    private func run(_ id: String) async throws {
        let all: [Scenario]
        do {
            all = try Self.scenarios.get()
        } catch {
            throw ScenarioFailure("scenario directory \(Self.scenarioDir.path) not readable (set HATANG_FIXTURES): \(error)")
        }
        guard let s = all.first(where: { $0.id == id }) else {
            throw ScenarioFailure("scenario \(id) not found in \(Self.scenarioDir.path)")
        }
        if let reason = skipReason(s) {
            throw XCTSkip("\(id) skipped: \(reason)")
        }
        let env = Self.env
        let base = (env["HATANG_CHAT_URL"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let vars = [
            "site_id": env["HATANG_SITE_ID"] ?? "",
            "app_key": env["HATANG_APP_KEY"] ?? "",
            "identity_secret": env["HATANG_IDENTITY_SECRET"] ?? "",
            "agent_token": env["HATANG_AGENT_TOKEN"] ?? "",
        ]
        let session = Self.session
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await runScenario(s, base: base, env: vars, session: session) }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw ScenarioFailure("\(id) did not finish within 30 s")
            }
            try await group.next()
            group.cancelAll()
        }
    }

    func testC01() async throws { try await run("C01") }
    func testC02() async throws { try await run("C02") }
    func testC03() async throws { try await run("C03") }
    func testC04() async throws { try await run("C04") }
    func testC05() async throws { try await run("C05") }
    func testC06() async throws { try await run("C06") }
    func testC07() async throws { try await run("C07") }
    func testC08() async throws { try await run("C08") }
    func testC09() async throws { try await run("C09") }
    func testC10() async throws { try await run("C10") }
    func testC11() async throws { try await run("C11") }
    func testC12() async throws { try await run("C12") }
}

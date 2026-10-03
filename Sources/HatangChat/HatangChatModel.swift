#if os(iOS)
import HatangChatCore
import Observation
import SwiftUI

/// The chat state for SwiftUI: mirrors the engine's `ChatState` on the main actor (fed by `states()`) and
/// forwards UI actions to the engine in order. `HatangChat.model` is the shared one; build your own with
/// `HatangChatModel(engine:)` to drive the views from another engine (tests, several sites).
@MainActor
@Observable
public final class HatangChatModel {
    /// The latest snapshot.
    public private(set) var state = ChatState()
    /// The engine behind it (nil before `HatangChat.configure`).
    public private(set) var engine: ChatEngine?
    /// How the views look (theme mode, theme overrides, strings).
    public var appearance = HatangChat.Appearance()
    /// How purchases from chat cards are handled.
    @ObservationIgnored public var commerce = HatangCommerce.standard
    /// Where UI-originated failures are logged.
    @ObservationIgnored var logger = HatangLogger.silent

    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var commands: AsyncStream<@Sendable (ChatEngine) async -> Void>.Continuation?
    @ObservationIgnored private var worker: Task<Void, Never>?

    /// A model with no engine yet (bind one with `HatangChat.configure`).
    public init() {}

    /// A model that follows `engine`.
    public init(engine: ChatEngine) {
        bind(engine)
    }

    // MARK: - ChatState mirror

    public var phase: ChatPhase { state.phase }
    public var connection: HatangConnectionState { state.connection }
    public var config: SiteConfig? { state.config }
    public var visitor: VisitorDto? { state.visitor }
    public var conversation: ConversationSummary? { state.conversation }
    public var timeline: Timeline { state.timeline }
    public var pending: [PendingMessage] { state.pending }
    public var typingAgent: String? { state.typingAgent }
    public var availability: Availability { state.availability }
    /// Messages received while the chat was not on screen.
    public var unread: Int { state.unread }
    public var locale: HatangLocale { state.locale }
    public var online: Bool { state.online }
    public var needsEmail: Bool { state.needsEmail }
    public var transientError: HatangError? { state.transientError }
    public var session: HatangSession { state.session }

    // MARK: - Binding

    /// Follows `engine` (or nothing): the previous feed stops and the state resets to the engine's current one.
    func bind(_ engine: ChatEngine?) {
        feed?.cancel()
        worker?.cancel()
        commands?.finish()
        self.engine = engine
        guard let engine else {
            state = ChatState()
            return
        }
        state = engine.currentState
        let stream = engine.states()
        feed = Task { [weak self] in
            for await s in stream {
                guard let self, !Task.isCancelled else { return }
                if self.state != s { self.state = s }
            }
        }
        let (cmds, c) = AsyncStream.makeStream(of: (@Sendable (ChatEngine) async -> Void).self)
        commands = c
        worker = Task {
            for await cmd in cmds { await cmd(engine) }
        }
    }

    /// Runs a quick engine action in order with the other quick actions (visibility, typing, rating).
    func fire(_ action: @escaping @Sendable (ChatEngine) async -> Void) {
        commands?.yield(action)
    }

    /// Runs a longer engine action (send, upload, load) on its own; failures are logged.
    func run(_ action: @escaping @Sendable (ChatEngine) async throws -> Void) {
        guard let engine else { return }
        let logger = self.logger
        Task {
            do {
                try await action(engine)
            } catch {
                logger.warn("chat action failed: \(error)")
            }
        }
    }
}
#endif

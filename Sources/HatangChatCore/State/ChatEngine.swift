import Foundation

/// The chat state machine: bootstrap → connect → ready → frames, plus every host-facing action. Pure
/// Foundation; the iOS layer wires storage, lifecycle and UI around it.
///
/// The engine is an actor, so its work is serialised without locks. Observe `states()` (each call gets
/// its own stream, current value first), `events()` and `openRequests()`; read `currentState` at any
/// time. Async actions finish when the work is done (a send, once acknowledged or failed).
public actor ChatEngine {
    private struct Hub {
        var state = ChatState()
        var token: String?
        var installId = ""
        var started = false
        var disposed = false
        var stateSubs: [UUID: AsyncStream<ChatState>.Continuation] = [:]
        var eventSubs: [UUID: AsyncStream<HatangEvent>.Continuation] = [:]
        var openSubs: [UUID: AsyncStream<String>.Continuation] = [:]
    }

    /// The REST client.
    public nonisolated let api: WidgetAPI
    /// How long after going to the background the socket is closed.
    public nonisolated let backgroundCloseDelay: Duration
    /// Idle time after the last keystroke before `typing off`.
    public nonisolated let typingIdle: Duration
    /// Delay before a failed bootstrap is retried (transient errors only).
    public nonisolated let bootstrapRetry: Duration
    /// Open the chat when the team starts a conversation with `open: true` (see `openRequests()`).
    public nonisolated let openOnProactiveMessage: Bool

    private let connector: any SocketConnector
    private let store: SessionStore
    private let appInfo: HatangAppInfo
    private let logger: HatangLogger
    private let backoff: Backoff
    private let clock: any HatangClock
    private let requestTimeout: Duration
    private let pingInterval: Duration
    private nonisolated let hub = Locked(Hub())

    private var st = ChatState()
    private var currentToken: String? {
        didSet { hub.withLock { [currentToken] in $0.token = currentToken } }
    }
    private var currentInstallId = "" {
        didSet { hub.withLock { [currentInstallId] in $0.installId = currentInstallId } }
    }
    private var started = false {
        didSet { hub.withLock { [started] in $0.started = started } }
    }
    private var disposed = false
    private var preferredLocale: String?
    private var stored = StoredSession.empty
    private var screen: ScreenInfo?
    private var socket: ChatSocket?
    private var socketSerial = 0
    private var cycle = 0
    private var readyEmitted = false
    private var backgroundTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var typingOn = false
    private var pushDirty = false
    private var pushRegisteredFor: String?
    private var loading: Task<Void, Never>?
    private var saveChain: Task<Void, Never>?
    private var refreshed = Set<String>()
    private var wantConversation: (id: String, summary: VisitorConversationDto?)?
    private var localIds = 0

    public init(
        api: WidgetAPI,
        connector: any SocketConnector,
        store: SessionStore,
        appInfo: HatangAppInfo,
        logger: HatangLogger = .silent,
        preferredLocale: String? = nil,
        backoff: Backoff = Backoff(),
        backgroundCloseDelay: Duration = .seconds(10),
        typingIdle: Duration = .seconds(3),
        bootstrapRetry: Duration = .seconds(5),
        openOnProactiveMessage: Bool = true,
        clock: any HatangClock = SystemClock(),
        requestTimeout: Duration = .seconds(10),
        pingInterval: Duration = .seconds(25)
    ) {
        self.api = api
        self.connector = connector
        self.store = store
        self.appInfo = appInfo
        self.logger = logger
        self.preferredLocale = preferredLocale
        self.backoff = backoff
        self.backgroundCloseDelay = backgroundCloseDelay
        self.typingIdle = typingIdle
        self.bootstrapRetry = bootstrapRetry
        self.openOnProactiveMessage = openOnProactiveMessage
        self.clock = clock
        self.requestTimeout = requestTimeout
        self.pingInterval = pingInterval
    }

    // MARK: - Observation

    /// The latest snapshot.
    public nonisolated var currentState: ChatState { hub.current.state }

    /// The current visitor token (after bootstrap).
    public nonisolated var token: String? { hub.current.token }

    /// The install id (after `start`).
    public nonisolated var installId: String { hub.current.installId }

    /// `start` was called and `stop` was not.
    public nonisolated var isStarted: Bool { hub.current.started }

    /// Every snapshot the UI renders, current value first. Each call returns its own stream; slow readers
    /// see the newest state (older ones are dropped).
    public nonisolated func states() -> AsyncStream<ChatState> {
        let (stream, c) = AsyncStream.makeStream(of: ChatState.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let alive = hub.withLock { h -> Bool in
            guard !h.disposed else { return false }
            c.yield(h.state)
            h.stateSubs[id] = c
            return true
        }
        if !alive {
            c.yield(currentState)
            c.finish()
        } else {
            c.onTermination = { [hub] _ in hub.withLock { _ = $0.stateSubs.removeValue(forKey: id) } }
        }
        return stream
    }

    /// Host-facing events from now on (not replayed: subscribe before `start`).
    public nonisolated func events() -> AsyncStream<HatangEvent> {
        let (stream, c) = AsyncStream.makeStream(of: HatangEvent.self, bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        let alive = hub.withLock { h -> Bool in
            guard !h.disposed else { return false }
            h.eventSubs[id] = c
            return true
        }
        if alive {
            c.onTermination = { [hub] _ in hub.withLock { _ = $0.eventSubs.removeValue(forKey: id) } }
        } else {
            c.finish()
        }
        return stream
    }

    /// Conversation ids the team opened proactively with `open: true`; the UI layer opens the screen.
    public nonisolated func openRequests() -> AsyncStream<String> {
        let (stream, c) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        let alive = hub.withLock { h -> Bool in
            guard !h.disposed else { return false }
            h.openSubs[id] = c
            return true
        }
        if alive {
            c.onTermination = { [hub] _ in hub.withLock { _ = $0.openSubs.removeValue(forKey: id) } }
        } else {
            c.finish()
        }
        return stream
    }

    /// Emits a host event from the UI layer (`.opened`, `.closed`).
    public nonisolated func emit(_ e: HatangEvent) {
        hub.withLock { h in
            guard !h.disposed else { return }
            for c in h.eventSubs.values { c.yield(e) }
        }
    }

    private func emit(_ s: ChatState) {
        if disposed { return }
        st = s
        hub.withLock { h in
            h.state = s
            for c in h.stateSubs.values { c.yield(s) }
        }
    }

    private func update(_ f: (inout ChatState) -> Void) {
        var s = st
        f(&s)
        emit(s)
    }

    private func event(_ e: HatangEvent) {
        if disposed { return }
        emit(e)
    }

    private func openRequest(_ id: String) {
        hub.withLock { h in
            for c in h.openSubs.values { c.yield(id) }
        }
    }

    // MARK: - Lifecycle

    /// Loads the stored session, bootstraps and connects.
    public func start() async {
        await startImpl()
    }

    private func startImpl() async {
        if disposed || started { return }
        started = true
        await ensureLoaded()
        let locale = pickLocale(preferred: preferredLocale ?? stored.locale, deviceLanguage: appInfo.deviceLocale)
        update { s in
            s.locale = locale
            s.visitorEmail = stored.email ?? s.visitorEmail
            s.visitorName = stored.name ?? s.visitorName
        }
        await bootstrapAndConnect()
    }

    /// Reads the stored session once. Every write goes through `persist` on top of it, so host calls made
    /// before `start` (push token, locale) never overwrite a stored visitor token with an empty session.
    private func ensureLoaded() async {
        if loading == nil {
            loading = Task { await self.loadStored() }
        }
        await loading?.value
    }

    private func loadStored() async {
        let s = await store.load()
        let install = await loadInstallId(store.installStore, now: clock.now())
        stored = s
        currentToken = s.token
        currentInstallId = install
    }

    /// Closes the socket and stops retrying; `start` may be called again.
    public func stop() {
        if disposed { return }
        started = false
        bootstrapTask?.cancel()
        bootstrapTask = nil
        closeSocket()
        update { $0.connection = .disconnected }
    }

    /// Releases every resource; the engine cannot be used afterwards. Streams finish.
    public func dispose() {
        if disposed { return }
        disposed = true
        started = false
        backgroundTask?.cancel()
        typingTask?.cancel()
        bootstrapTask?.cancel()
        closeSocket()
        let subs = hub.withLock { h -> ([AsyncStream<ChatState>.Continuation], [AsyncStream<HatangEvent>.Continuation], [AsyncStream<String>.Continuation]) in
            h.disposed = true
            defer {
                h.stateSubs = [:]
                h.eventSubs = [:]
                h.openSubs = [:]
            }
            return (Array(h.stateSubs.values), Array(h.eventSubs.values), Array(h.openSubs.values))
        }
        subs.0.forEach { $0.finish() }
        subs.1.forEach { $0.finish() }
        subs.2.forEach { $0.finish() }
    }

    /// Opens the socket again after `stop` or a background close (bootstraps first when it never ran).
    public func connect() async {
        if disposed { return }
        if !started {
            await startImpl()
            return
        }
        guard st.phase == .ready, let s = socket else {
            await bootstrapAndConnect()
            return
        }
        s.connect()
    }

    private func closeSocket() {
        let s = socket
        socket = nil
        cycle += 1
        s?.close()
    }

    private func persist(_ s: StoredSession) async {
        stored = s
        await save(s)
    }

    /// `stored` changes now; the write happens in order soon after.
    private func persistLater(_ s: StoredSession) {
        stored = s
        _ = enqueueSave(s)
    }

    private func save(_ s: StoredSession) async {
        await enqueueSave(s).value
    }

    private func enqueueSave(_ s: StoredSession) -> Task<Void, Never> {
        let previous = saveChain
        let store = self.store
        let logger = self.logger
        let t = Task {
            await previous?.value
            do {
                try await store.save(s)
            } catch {
                logger.warn("persist failed: \(error)")
            }
        }
        saveChain = t
        return t
    }

    // MARK: - Bootstrap

    private func bootstrapAndConnect() async {
        if disposed || !started { return }
        // A foreground change or connect() can get here while start() is still loading the stored session;
        // bootstrapping before that would send an empty install id and no token.
        await ensureLoaded()
        if disposed || !started { return }
        closeSocket()
        let cycle = self.cycle
        readyEmitted = false
        if st.phase == .outdated { return }
        update { s in
            s.phase = .bootstrapping
            s.connection = .connecting
            s.transientError = nil
        }
        let boot: BootstrapResponse
        do {
            boot = try await api.bootstrap(
                app: appInfo.context(installId: currentInstallId, locale: st.locale.code),
                token: currentToken,
                screen: screen,
                locale: st.locale.code
            )
        } catch {
            if cycle != self.cycle || disposed || !started { return }
            if error is CancellationError { return }
            let e = (error as? HatangError) ?? HatangError.network("\(error)")
            logger.warn("bootstrap failed: \(e)")
            if e.isTokenError, currentToken != nil {
                // The stored token is dead: start over as a new visitor.
                currentToken = nil
                var s = stored
                s.token = nil
                await persist(s.withoutConversation())
                Task { await self.bootstrapAndConnect() }
                return
            }
            let fatal = e.isAppKeyError || ((e.status.map { $0 < 500 } ?? false) && !e.isRateLimit)
            update { s in
                if fatal { s.phase = .failed }
                s.connection = .disconnected
                s.transientError = e
            }
            if !fatal {
                bootstrapTask?.cancel()
                let wait = bootstrapRetry
                let clock = self.clock
                bootstrapTask = Task {
                    do { try await clock.sleep(for: wait) } catch { return }
                    self.bootstrapTask = nil
                    if cycle == self.cycle && self.started { await self.bootstrapAndConnect() }
                }
            }
            return
        }
        if cycle != self.cycle || disposed || !started { return }
        if boot.protocolVersion > protocolVersion {
            outdated("gateway speaks protocol \(boot.protocolVersion)")
            return
        }
        currentToken = boot.visitorToken
        let locale = pickLocale(
            preferred: preferredLocale ?? stored.locale,
            siteDefault: boot.config.localeDefault,
            deviceLanguage: appInfo.deviceLocale
        )
        let conv = boot.conversation
        let timeline = mergeTimeline(.empty, boot.timeline)
        var next = stored
        next.token = boot.visitorToken
        if let conv {
            let same = conv.id == stored.conversationId
            next.conversationId = conv.id
            next.lastSeq = same ? max(timeline.lastSeq, stored.lastSeq) : timeline.lastSeq
        } else {
            next = next.withoutConversation()
        }
        await persist(next)
        if cycle != self.cycle || disposed || !started { return }
        update { s in
            s.phase = .ready
            s.config = boot.config
            s.visitor = boot.visitor
            s.conversation = conv
            var t = timeline
            t.hasMore = ChatEngine.olderExist(timeline, boot.timelineHasMore)
            s.timeline = t
            s.availability = boot.availability
            s.locale = locale
            s.unread = s.visible ? 0 : (conv?.visitorUnread ?? 0)
            s.visitorEmail = boot.visitor.email ?? s.visitorEmail
            s.visitorName = boot.visitor.name ?? s.visitorName
            s.pending = []
            s.typingAgent = nil
            s.needsEmail = false
        }
        logger.info("bootstrapped visitor \(boot.visitor.id) (conversation \(conv?.id ?? "none"))")
        openSocket(boot.wsUrl)
    }

    private func outdated(_ reason: String) {
        closeSocket()
        update { s in
            s.phase = .outdated
            s.connection = .outdated
            s.outdatedReason = reason
        }
        event(.protocolOutdated(reason: reason))
    }

    // MARK: - Socket

    private func openSocket(_ url: String) {
        socketSerial += 1
        let serial = socketSerial
        let handlers = ChatSocket.Handlers(
            onFrame: { [weak self] f in await self?.onFrame(f, serial: serial) },
            onStatus: { [weak self] s in await self?.onStatus(s, serial: serial) },
            onClose: { [weak self] code, reason in await self?.onClose(code, reason, serial: serial) }
        )
        let s = ChatSocket(
            url: url,
            connector: connector,
            auth: { [weak self] in
                guard let self else { throw HatangError.closed }
                return try await self.authPayload()
            },
            handlers: handlers,
            backoff: backoff,
            requestTimeout: requestTimeout,
            pingInterval: pingInterval,
            logger: logger,
            clock: clock
        )
        socket = s
        s.connect()
    }

    private func authPayload() throws -> JSONObject {
        guard let token = currentToken else { throw HatangError(code: "no_token", message: "No visitor token") }
        return ClientFrame.auth(
            token: token,
            siteId: api.siteId,
            screen: screen,
            app: appInfo.context(installId: currentInstallId, locale: st.locale.code),
            client: appInfo.client,
            locale: st.locale.code,
            foreground: st.foreground
        ).d ?? [:]
    }

    private func onStatus(_ s: SocketStatus, serial: Int) {
        guard serial == socketSerial, socket != nil, st.phase != .outdated else { return }
        update { st in
            switch s {
            case .connecting: st.connection = .connecting
            case .open: st.connection = .connected
            case .closed: st.connection = .disconnected
            }
        }
    }

    private func onClose(_ code: Int, _ reason: String, serial: Int) async {
        guard serial == socketSerial, socket != nil else { return }
        logger.debug("socket closed \(code) \(reason)")
        switch code {
        case CloseCodes.authFailed:
            // Token refused or revoked: forget it and start over as a fresh visitor.
            currentToken = nil
            closeSocket()
            var s = stored
            s.token = nil
            await persist(s.withoutConversation())
            update { st in
                st.conversation = nil
                st.timeline = .empty
                st.pending = []
                st.unread = 0
            }
            await bootstrapAndConnect()
            if let v = st.visitor { event(.sessionChanged(visitorId: v.id, reason: .tokenRejected)) }
        case CloseCodes.protocolOutdated:
            outdated(reason.isEmpty ? "protocol outdated" : reason)
        default:
            break
        }
    }

    private func send(_ f: ClientFrame) {
        socket?.send(f)
    }

    // MARK: - Frames

    private func onFrame(_ f: ServerFrame, serial: Int) async {
        guard serial == socketSerial, socket != nil, !disposed else { return }
        switch f {
        case .ready(let r):
            onReady(r)
        case .message(let m):
            onMessage(m.message)
        case .event(let e):
            onEvent(e.event)
        case .typing(let t):
            if t.side == "agent", t.conversationId == st.conversation?.id {
                update { $0.typingAgent = t.on ? (t.name ?? "") : nil }
            }
        case .availability(let a):
            update { $0.availability = a.availability }
        case .read(let r):
            if r.side == "agent", r.conversationId == st.conversation?.id {
                let now = clock.now()
                update { $0.timeline = applyRead($0.timeline, side: "agent", upTo: r.upToSeq, now: now) }
            }
        case .resume(let r):
            if r.conversationId == st.conversation?.id { mergeItems(r.items) }
        case .conversationStart(let s):
            onConversationStart(s)
        case .conversationUpdate(let u):
            if let c = st.conversation, c.id == u.conversation.id {
                let changed = c.status != u.conversation.status
                var next = c
                next.status = u.conversation.status
                next.seq = u.conversation.seq
                update { $0.conversation = next }
                if changed { event(.conversationStatus(conversationId: c.id, status: u.conversation.status)) }
            }
        case .conversationUpsert(let u):
            if let c = st.conversation, c.id == u.conversation.id {
                update { $0.conversation = u.conversation }
            }
        case .session(let s):
            await onSession(s)
        case .reload(let r):
            logger.info("reload requested: \(r.reason)")
            Task { await self.bootstrapAndConnect() }
        case .error(let e):
            if e.id == nil {
                update { $0.transientError = HatangError(code: e.code, message: e.message) }
            }
        case .messageAck, .pong, .unknown:
            break
        }
    }

    private func onReady(_ f: ReadyFrame) {
        let previousLastSeq = max(st.timeline.lastSeq, stored.lastSeq)
        var s = st
        s.phase = .ready
        s.connection = .connected
        s.visitor = f.visitor
        s.availability = f.availability
        s.visitorEmail = f.visitor.email ?? s.visitorEmail
        s.visitorName = f.visitor.name ?? s.visitorName
        let conv = f.conversation
        if let conv {
            let replaced = conv.id != st.conversation?.id
            var timeline = mergeTimeline(replaced ? .empty : st.timeline, f.timeline)
            timeline.hasMore = replaced ? ChatEngine.olderExist(timeline, f.timelineHasMore) : (f.timelineHasMore ?? timeline.hasMore)
            s.conversation = conv
            s.timeline = timeline
            s.pending = reconcilePending(st.pending, f.timeline)
        }
        emit(s)
        let cid = conv?.id ?? st.conversation?.id
        if let cid, previousLastSeq > 0, conv == nil || conv?.id == stored.conversationId {
            send(.resume(conversationId: cid, afterSeq: previousLastSeq))
        }
        if let conv, conv.id != stored.conversationId {
            var next = stored
            next.conversationId = conv.id
            next.lastSeq = st.timeline.lastSeq
            persistLater(next)
        }
        send(.appState(foreground: st.foreground, conversationId: st.visible ? cid : nil))
        if st.canRead, let cid, st.timeline.lastSeq > 0 { send(.read(conversationId: cid, upToSeq: st.timeline.lastSeq)) }
        Task { await self.flushPush() }
        if let want = wantConversation {
            wantConversation = nil
            if want.id != st.conversation?.id {
                Task { await self.openConversationImpl(want.id, want.summary) }
            }
        }
        if !readyEmitted {
            readyEmitted = true
            event(.ready(visitorId: f.visitor.id, conversationId: cid))
        }
    }

    private func mergeItems(_ items: [TimelineItem], hasMore: Bool? = nil) {
        let timeline = mergeTimeline(st.timeline, items, hasMore: hasMore)
        update { s in
            s.timeline = timeline
            s.pending = reconcilePending(s.pending, items)
        }
        if timeline.lastSeq != stored.lastSeq {
            var next = stored
            next.lastSeq = timeline.lastSeq
            persistLater(next)
        }
    }

    private func onMessage(_ m: MessageDto) {
        guard let conv = st.conversation, m.conversationId == conv.id else { return }
        mergeItems([.message(m)])
        update { $0.typingAgent = nil }
        if m.isMine {
            event(.messageSent(m))
            return
        }
        event(.messageReceived(m))
        if let md = m.metadata, md.str("kind") == "order_paid" {
            event(.conversion(HatangConversion(kind: .purchase, data: [
                "value": .number(md.num("value") ?? 0),
                "currency": "VND",
                "transaction_id": .string(md.str("code") ?? ""),
            ])))
        }
        if st.canRead {
            send(.read(conversationId: conv.id, upToSeq: m.seq))
        } else {
            update { $0.unread += 1 }
        }
    }

    private func onEvent(_ e: ConversationEventDto) {
        guard let conv = st.conversation, e.conversationId == conv.id else { return }
        mergeItems([.event(e)])
        if e.type == "status_changed" {
            let to = ConversationStatus.parse(e.data.str("to"))
            update { s in
                var c = s.conversation ?? conv
                c.status = to
                s.conversation = c
            }
            event(.conversationStatus(conversationId: conv.id, status: to))
        } else if e.type == "rated", st.rated == nil {
            let score = e.data.str("score").flatMap { Int($0) } ?? 5
            update { $0.rated = score }
        }
    }

    private func onConversationStart(_ f: ConversationStartFrame) {
        if st.conversation?.id == f.conversation.id { return }
        update { s in
            s.conversation = f.conversation
            s.timeline = .empty
            s.pending = []
            s.typingAgent = nil
            s.rated = nil
        }
        var next = stored
        next.conversationId = f.conversation.id
        next.lastSeq = 0
        persistLater(next)
        // Messages posted before this frame: replay from the start.
        send(.resume(conversationId: f.conversation.id, afterSeq: 0))
        if f.open, openOnProactiveMessage, !st.visible { openRequest(f.conversation.id) }
    }

    private func onSession(_ f: SessionFrame) async {
        // Identity merged into another visitor: keep the new token and start over with it (the gateway
        // closes the socket with 4005 right after).
        currentToken = f.visitorToken
        var next = stored
        next.token = f.visitorToken
        await persist(next.withoutConversation())
        update { s in
            s.conversation = nil
            s.timeline = .empty
            s.pending = []
            s.unread = 0
        }
        await bootstrapAndConnect()
        event(.sessionChanged(visitorId: f.visitorId, reason: f.reason == "reset" ? .reset : .identityMerged))
    }

    // MARK: - Send

    /// Sends `text` (trimmed; blank text is ignored). Shows the pre-chat form instead when the team is away
    /// and the site wants an email. Returns once the message is acknowledged or marked failed.
    public func send(_ text: String) async {
        if disposed { return }
        await sendImpl(text)
    }

    private func sendImpl(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return }
        if !st.online, let cfg = st.config, cfg.offlineCapture != .off, (st.visitorEmail ?? "").isEmpty, !st.skippedEmail {
            update { s in
                s.needsEmail = true
                s.draft = content
            }
            return
        }
        let now = clock.now()
        let p = PendingMessage(clientId: newClientId(now), content: content, createdAt: now)
        update { s in
            s.pending.append(p)
            s.draft = nil
        }
        stopTyping()
        await sendPending(p)
    }

    /// Sends a file, optionally with a `caption`. It shows at once as a pending bubble with upload
    /// progress; when the bytes are on the server the message goes out like text (same retry by client id).
    /// Files over 10 MB or of a type the gateway refuses fail immediately with a transient error.
    public func attach(_ source: UploadSource, caption: String = "") async {
        if disposed { return }
        if source.size > Limits.attachmentBytes {
            update { $0.transientError = HatangError(code: "file_too_large", message: "Files must be 10 MB or smaller") }
            return
        }
        if !uploadMimeTypes.contains(source.mimeType) {
            update { $0.transientError = HatangError(code: "unsupported_file_type", message: "File type \(source.mimeType) is not allowed") }
            return
        }
        let now = clock.now()
        let p = PendingMessage(
            clientId: newClientId(now),
            content: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            upload: PendingUpload(source: source)
        )
        update { $0.pending.append(p) }
        await uploadThenSend(p)
    }

    /// Re-sends a failed message with the same client id (re-uploading its file first if it never finished).
    public func retry(_ clientId: String) async {
        if disposed { return }
        guard var p = pendingById(clientId) else { return }
        p.failed = false
        p.errorCode = nil
        replacePending(p)
        await uploadThenSend(p)
    }

    private func pendingById(_ clientId: String) -> PendingMessage? {
        st.pending.first { $0.clientId == clientId }
    }

    private func uploadThenSend(_ start: PendingMessage) async {
        var q = start
        if let up = q.upload, !up.done {
            guard let token = currentToken else {
                q.failed = true
                q.errorCode = "closed"
                replacePending(q)
                return
            }
            let shown = Locked(0.0)
            let clientId = q.clientId
            do {
                let a = try await api.upload(token: token, data: up.source.data, filename: up.source.name, contentType: up.source.mimeType) { [weak self] sent, total in
                    let f = total > 0 ? Double(sent) / Double(total) : 0
                    let repaint = shown.withLock { last -> Bool in
                        if f - last < 0.05, f < 1 { return false } // repaint every 5 %
                        last = f
                        return true
                    }
                    guard repaint, let self else { return }
                    Task { await self.uploadProgress(clientId, f) }
                }
                guard var cur = pendingById(clientId) else { return } // dismissed meanwhile
                var u = cur.upload ?? up
                u.progress = 1
                u.uploadedId = a.id
                cur.attachments = [a.id]
                cur.upload = u
                q = cur
                replacePending(q)
            } catch {
                if error is CancellationError { return }
                logger.warn("upload failed: \(error)")
                let e = error as? HatangError
                if pendingById(clientId) != nil {
                    q.failed = true
                    q.errorCode = e?.code ?? "network_error"
                    replacePending(q)
                }
                if let e { update { $0.transientError = e } }
                return
            }
        }
        await sendPending(q)
    }

    private func uploadProgress(_ clientId: String, _ f: Double) {
        guard var cur = pendingById(clientId), var u = cur.upload, !u.done else { return }
        u.progress = f
        cur.upload = u
        replacePending(cur)
    }

    /// Signed attachment links expire after a day. When one fails to load, fetch that message again for
    /// fresh links (once per message per session).
    public func refreshAttachments(_ message: MessageDto) async {
        if disposed { return }
        guard let token = currentToken, message.seq > 0, !refreshed.contains(message.id) else { return }
        refreshed.insert(message.id)
        do {
            let page = try await api.messages(token: token, conversationId: message.conversationId, afterSeq: message.seq - 1, limit: 1)
            mergeItems(page.items)
        } catch {
            logger.warn("attachment refresh failed: \(error)")
        }
    }

    private func replacePending(_ p: PendingMessage) {
        update { s in
            s.pending = s.pending.map { $0.clientId == p.clientId ? p : $0 }
        }
    }

    private func removePending(_ clientId: String) {
        update { s in
            s.pending.removeAll { $0.clientId == clientId }
        }
    }

    private func sendPending(_ p: PendingMessage) async {
        guard let socket else {
            var f = p
            f.failed = true
            f.errorCode = "closed"
            replacePending(f)
            return
        }
        let conv = st.conversation
        do {
            let reply = try await socket.request(.send(clientId: p.clientId, content: p.content, conversationId: conv?.id, attachments: p.attachments))
            guard case .messageAck(let ack) = reply else {
                throw HatangError(code: "bad_ack", message: "Unexpected reply \(reply.t)")
            }
            if !st.pending.contains(where: { $0.clientId == p.clientId }) { return }
            var adopted = false
            let cur = st.conversation
            if cur == nil || cur?.id != ack.conversationId {
                adopted = cur == nil
                let c = ConversationSummary(id: ack.conversationId, siteId: api.siteId, visitorId: st.visitor?.id ?? "")
                update { s in
                    s.conversation = c
                    s.timeline = .empty
                }
                var next = stored
                next.conversationId = c.id
                next.lastSeq = 0
                persistLater(next)
            }
            var attachments: [Attachment] = []
            if let up = p.upload, let uploadedId = up.uploadedId {
                attachments = [Attachment(id: uploadedId, name: up.source.name, size: up.source.size, type: up.source.mimeType)]
            }
            let local = MessageDto(
                id: ack.messageId,
                conversationId: ack.conversationId,
                seq: ack.seq,
                senderType: .visitor,
                content: p.content,
                createdAt: p.createdAt,
                senderId: st.visitor?.id,
                attachments: attachments,
                clientId: p.clientId
            )
            removePending(p.clientId)
            mergeItems([.message(local)])
            if adopted {
                event(.conversion(HatangConversion(kind: .chatStarted)))
                // Frames for this brand-new conversation may have arrived before we knew its id.
                send(.resume(conversationId: ack.conversationId, afterSeq: 0))
            }
        } catch {
            let e = (error as? HatangError) ?? HatangError.network("\(error)")
            logger.warn("send failed: \(e)")
            if st.pending.contains(where: { $0.clientId == p.clientId }) {
                var f = p
                f.failed = true
                f.errorCode = e.code
                replacePending(f)
            }
            update { $0.transientError = e }
        }
    }

    // MARK: - Composer / UI

    /// The composer text changed: sends one `typing on`, then `off` after `typingIdle` without keystrokes.
    public func onTextChanged(_ text: String) {
        guard !disposed, let conv = st.conversation else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stopTyping()
            return
        }
        if !typingOn {
            typingOn = true
            send(.typing(conversationId: conv.id, on: true))
        }
        typingTask?.cancel()
        let wait = typingIdle
        let clock = self.clock
        typingTask = Task {
            do { try await clock.sleep(for: wait) } catch { return }
            self.typingTask = nil
            self.stopTyping()
        }
    }

    private func stopTyping() {
        typingTask?.cancel()
        typingTask = nil
        guard typingOn else { return }
        typingOn = false
        if let c = st.conversation { send(.typing(conversationId: c.id, on: false)) }
    }

    /// The conversation is (not) on screen. Visible clears unread and sends a read receipt for everything
    /// loaded.
    public func setVisible(_ visible: Bool) {
        guard !disposed, st.visible != visible else { return }
        update { s in
            s.visible = visible
            if visible { s.unread = 0 }
        }
        let conv = st.conversation
        if visible, let conv, st.timeline.lastSeq > 0, st.foreground {
            send(.read(conversationId: conv.id, upToSeq: st.timeline.lastSeq))
        }
        if socket?.ready == true { send(.appState(foreground: st.foreground, conversationId: visible ? conv?.id : nil)) }
    }

    /// The app moved to the foreground or background. In the background the gateway is told at once
    /// (`app.state`) and the socket closes after `backgroundCloseDelay`; back in the foreground it
    /// reconnects.
    public func setForeground(_ foreground: Bool) {
        guard !disposed, st.foreground != foreground else { return }
        update { $0.foreground = foreground }
        backgroundTask?.cancel()
        backgroundTask = nil
        if foreground {
            if let socket {
                if !socket.active {
                    socket.connect()
                } else {
                    send(.appState(foreground: true, conversationId: st.visible ? st.conversation?.id : nil))
                    if st.visible, let conv = st.conversation, st.timeline.lastSeq > 0 {
                        send(.read(conversationId: conv.id, upToSeq: st.timeline.lastSeq))
                    }
                }
            } else if started, st.phase != .outdated {
                Task { await self.bootstrapAndConnect() }
            }
        } else {
            send(.appState(foreground: false))
            stopTyping()
            let wait = backgroundCloseDelay
            let clock = self.clock
            backgroundTask = Task {
                do { try await clock.sleep(for: wait) } catch { return }
                self.backgroundTask = nil
                self.closeForBackground()
            }
        }
    }

    private func closeForBackground() {
        guard !st.foreground else { return }
        socket?.close()
        update { $0.connection = .disconnected }
    }

    /// Loads the page before the oldest loaded item.
    public func loadEarlier() async {
        guard !disposed, let conv = st.conversation, let token = currentToken, !st.loadingEarlier, st.timeline.hasMore else { return }
        let oldest = st.timeline.oldestSeq
        if oldest <= 1 {
            update { $0.timeline.hasMore = false }
            return
        }
        update { $0.loadingEarlier = true }
        do {
            let page = try await api.messages(token: token, conversationId: conv.id, beforeSeq: oldest, limit: 50)
            if st.conversation?.id != conv.id { return }
            update { $0.loadingEarlier = false }
            mergeItems(page.items, hasMore: page.hasMore && !page.items.isEmpty)
        } catch {
            let e = (error as? HatangError) ?? HatangError.network("\(error)")
            update { s in
                s.loadingEarlier = false
                s.transientError = e
            }
        }
    }

    // MARK: - History

    /// The visitor's conversations, newest activity first, resolved ones included (an in-app inbox).
    /// `status` is `all`, `open` or `resolved`; pass the last id of a page as `after` for the next one.
    public func listConversations(status: String = "all", after: String? = nil, limit: Int = 20) async throws -> ConversationPage {
        if disposed { return ConversationPage(conversations: [], hasMore: false) }
        return try await listConversationsImpl(status, after, limit)
    }

    private func listConversationsImpl(_ status: String, _ after: String?, _ limit: Int) async throws -> ConversationPage {
        guard let token = currentToken else { return ConversationPage(conversations: [], hasMore: false) }
        return try await api.listConversations(token: token, status: status, limit: limit, after: after)
    }

    /// Shows conversation `id`: its latest 50 items, live updates while it is on screen, earlier ones
    /// through `loadEarlier`. Writing into a resolved conversation reopens it; a closed one is read-only.
    /// `summary` (from `listConversations`) avoids a flash of the wrong status. Before the session is ready
    /// the request is remembered and honoured on `ready` (a notification tap on a cold start).
    public func openConversation(_ id: String, summary: VisitorConversationDto? = nil) async {
        if disposed { return }
        await openConversationImpl(id, summary)
    }

    private func openConversationImpl(_ id: String, _ summary: VisitorConversationDto?) async {
        if st.conversation?.id == id { return }
        guard let token = currentToken, st.phase == .ready else {
            wantConversation = (id, summary) // opened once the session is ready
            return
        }
        let siteId = api.siteId
        update { s in
            s.conversation = ConversationSummary(
                id: id,
                siteId: siteId,
                visitorId: s.visitor?.id ?? "",
                status: summary?.status ?? .open,
                seq: summary?.seq ?? 0
            )
            s.timeline = .empty
            s.loadingEarlier = true
            s.typingAgent = nil
            s.rated = nil
        }
        do {
            // Latest page: everything before seq + 1 (the gateway stores seq as a 32-bit integer).
            let top = (summary?.seq ?? 0) > 0 ? summary!.seq + 1 : ChatEngine.maxSeq
            let page = try await api.messages(token: token, conversationId: id, beforeSeq: top, limit: 50)
            if st.conversation?.id != id { return }
            var timeline = mergeTimeline(.empty, page.items)
            timeline.hasMore = page.hasMore
            update { s in
                s.loadingEarlier = false
                s.timeline = timeline
            }
            afterSwitch(id)
        } catch {
            let e = (error as? HatangError) ?? HatangError.network("\(error)")
            update { s in
                s.loadingEarlier = false
                s.transientError = e
            }
        }
    }

    /// Back to the visitor's current conversation (the newest open one), or an empty chat when there is
    /// none, so the next message starts a new one.
    public func openActive() async throws {
        if disposed { return }
        let page = try await listConversationsImpl("open", nil, 1)
        if let open = page.conversations.first {
            await openConversationImpl(open.id, open)
            return
        }
        if st.conversation == nil { return }
        update { s in
            s.conversation = nil
            s.timeline = .empty
            s.typingAgent = nil
            s.rated = nil
        }
        persistLater(stored.withoutConversation())
    }

    /// A switch landed: the thread on screen gets focus and read receipts; an open one is resumed after
    /// restarts.
    private func afterSwitch(_ id: String) {
        if let conv = st.conversation, conv.status.isActive {
            var next = stored
            next.conversationId = id
            next.lastSeq = st.timeline.lastSeq
            persistLater(next)
        }
        send(.appState(foreground: st.foreground, conversationId: st.visible ? id : nil))
        if st.canRead, st.timeline.lastSeq > 0 {
            send(.read(conversationId: id, upToSeq: st.timeline.lastSeq))
            update { $0.unread = 0 }
        }
    }

    /// Inline email request answered: identifies the visitor by email, then sends the held-back draft.
    public func submitEmail(_ email: String) async {
        if disposed { return }
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { return }
        send(.identify(email: e))
        update { s in
            s.visitorEmail = e
            s.needsEmail = false
        }
        var next = stored
        next.email = e
        await persist(next)
        addLocalNotice("emailSaved")
        await sendDraft()
    }

    /// Offline pre-chat form: posts the first message (or the held-back draft) with name and email.
    public func submitOfflineForm(name: String? = nil, email: String? = nil, message: String? = nil) async {
        guard !disposed, let token = currentToken else { return }
        let given = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = given.isEmpty ? (st.draft ?? "") : given
        if text.isEmpty { return }
        do {
            let r = try await api.offlineMessage(token: token, message: text, name: name, email: email)
            let sameConversation = st.conversation?.id == r.conversation.id
            let cleanEmail = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            update { s in
                s.conversation = r.conversation
                s.needsEmail = false
                s.draft = nil
                if !cleanEmail.isEmpty { s.visitorEmail = cleanEmail }
                if !cleanName.isEmpty { s.visitorName = cleanName }
                if !sameConversation { s.timeline = .empty }
            }
            var next = stored
            next.conversationId = r.conversation.id
            if !cleanEmail.isEmpty { next.email = cleanEmail }
            if !cleanName.isEmpty { next.name = cleanName }
            await persist(next)
            send(.resume(conversationId: r.conversation.id, afterSeq: 0))
            addLocalNotice("emailSaved")
            event(.conversion(HatangConversion(kind: .chatStarted)))
        } catch {
            let e = (error as? HatangError) ?? HatangError.network("\(error)")
            update { $0.transientError = e }
        }
    }

    /// The visitor declined the optional email; the held-back draft is sent.
    public func skipEmail() async {
        if disposed { return }
        update { s in
            s.skippedEmail = true
            s.needsEmail = false
        }
        await sendDraft()
    }

    /// Dismisses the pre-chat form without sending.
    public func cancelEmailForm() {
        if disposed { return }
        update { s in
            s.needsEmail = false
            s.draft = nil
        }
    }

    private func sendDraft() async {
        guard let draft = st.draft, !draft.isEmpty else { return }
        update { $0.draft = nil }
        await sendImpl(draft)
    }

    private func localId(_ now: Date) -> String {
        localIds += 1
        let micros = Int64((now.timeIntervalSince1970 * 1_000_000).rounded(.down))
        return "local-\(micros)-\(localIds)"
    }

    private func addLocalNotice(_ key: String) {
        let now = clock.now()
        mergeItems([.event(ConversationEventDto(
            id: localId(now),
            conversationId: st.conversation?.id ?? "",
            seq: st.timeline.lastSeq,
            type: "notice",
            createdAt: now,
            data: ["key": .string(key)]
        ))])
    }

    /// Rates the conversation (CSAT, `score` 1–5).
    public func rate(_ score: Int, comment: String? = nil) {
        guard !disposed, let conv = st.conversation else { return }
        send(.rate(conversationId: conv.id, score: score, comment: comment))
        update { $0.rated = score }
    }

    /// Inserts a local-only bot bubble (never sent, never persisted).
    public func showLocalMessage(_ text: String, senderName: String? = nil) {
        if disposed { return }
        let now = clock.now()
        mergeItems([.message(MessageDto(
            id: localId(now),
            conversationId: st.conversation?.id ?? "",
            seq: st.timeline.lastSeq,
            senderType: .bot,
            content: text,
            createdAt: now,
            senderName: senderName
        ))])
    }

    /// Clears the error banner.
    public func clearTransientError() {
        update { $0.transientError = nil }
    }

    // MARK: - Session

    /// Attaches an identity. Returns once the gateway acknowledged it (or, on a merge, once the new session
    /// started). Throws `HatangError` (`closed`, `timeout`, or the gateway's code).
    public func identify(_ user: HatangUser) async throws {
        if disposed { throw HatangError.closed }
        if user.isEmpty { return }
        guard let socket else { throw HatangError.closed }
        let reply = try await socket.request(
            .identify(userId: user.userId, email: user.email, name: user.name, phone: user.phone, hash: user.hash, data: user.data),
            timeout: .seconds(15)
        )
        if case .session = reply { return } // onSession restarts the session.
        update { s in
            s.visitorEmail = user.email ?? s.visitorEmail
            s.visitorName = user.name ?? s.visitorName
            s.needsEmail = false
        }
        var next = stored
        next.email = user.email ?? stored.email
        next.name = user.name ?? stored.name
        await persist(next)
    }

    /// Attaches custom data (shown to agents).
    public func setData(_ data: JSONObject) async throws {
        try await identify(HatangUser(data: data))
    }

    /// Records a custom event on the active conversation.
    public func pushEvent(_ name: String, data: JSONObject? = nil) {
        if disposed { return }
        send(.event(name: name, data: data))
    }

    /// Switches the UI language; the socket re-authenticates so the gateway learns it too.
    public func setLocale(_ locale: HatangLocale) async {
        if disposed { return }
        await ensureLoaded()
        preferredLocale = locale.code
        if st.locale == locale { return }
        update { $0.locale = locale }
        var next = stored
        next.locale = locale.code
        await persist(next)
        if let s = socket, s.active {
            s.close()
            s.connect()
        }
    }

    /// Reports the screen the app shows (sent now when connected, and on every auth).
    public func setScreen(_ name: String, params: [String: String]? = nil) {
        if disposed { return }
        let s = ScreenInfo(name: name, params: params)
        screen = s
        if socket?.ready == true { send(.screen(s)) }
    }

    /// Forgets this visitor: the old token stops working, a fresh visitor is bootstrapped and the push
    /// token (if any) is re-registered for it. Before `start` the stored visitor is forgotten all the
    /// same, and the new one connects on the next `start`.
    public func reset() async throws {
        if disposed { return }
        await ensureLoaded()
        guard let old = currentToken else { return }
        let r = try await api.reset(token: old, installId: currentInstallId)
        let push = stored.pushToken
        if let push {
            do {
                try await api.deleteDevice(token: old, pushToken: push)
            } catch {
                logger.warn("device removal failed: \(error)")
            }
        }
        closeSocket()
        currentToken = r.visitorToken
        pushRegisteredFor = nil
        pushDirty = push != nil
        await persist(StoredSession(
            token: r.visitorToken,
            locale: stored.locale,
            pushToken: stored.pushToken,
            pushProvider: stored.pushProvider
        ))
        var fresh = ChatState()
        fresh.phase = .bootstrapping
        fresh.connection = .connecting
        fresh.locale = st.locale
        fresh.visible = st.visible
        fresh.foreground = st.foreground
        fresh.config = st.config
        emit(fresh)
        if started { await bootstrapAndConnect() }
        event(.sessionChanged(visitorId: r.visitorId, reason: .reset))
    }

    /// Swaps a magic-link token (`…/c/<token>` from a "we replied" email) for that session.
    public func restoreSession(_ linkToken: String) async throws {
        if disposed { return }
        await ensureLoaded()
        let r = try await api.restoreSession(linkToken: linkToken)
        closeSocket()
        currentToken = r.visitorToken
        pushRegisteredFor = nil
        pushDirty = stored.pushToken != nil
        var next = stored
        next.token = r.visitorToken
        next.conversationId = r.conversationId
        next.lastSeq = 0
        next.email = nil
        next.name = nil
        await persist(next)
        update { s in
            s.conversation = nil
            s.timeline = .empty
            s.pending = []
            s.unread = 0
        }
        await bootstrapAndConnect()
        event(.sessionChanged(visitorId: r.visitorId, reason: .restored))
    }

    // MARK: - Push

    /// Remembers the push token and registers it (`PUT devices`) once a visitor token exists.
    public func setPushToken(_ token: String, provider: PushProvider) async {
        if disposed { return }
        await ensureLoaded()
        if stored.pushToken == token, stored.pushProvider == provider.code, pushRegisteredFor == currentToken,
           stored.pushAppVersion == appInfo.version {
            return
        }
        var next = stored
        next.pushToken = token
        next.pushProvider = provider.code
        next.pushAppVersion = appInfo.version
        await persist(next)
        pushRegisteredFor = nil
        pushDirty = true
        await flushPush()
    }

    /// Registers the APNs device token from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// (sent as lower-case hex with provider `apns`).
    public func setPushToken(apnsDeviceToken: Data) async {
        await setPushToken(apnsDeviceToken.map { String(format: "%02x", $0) }.joined(), provider: .apns)
    }

    /// Unregisters the push token (`DELETE devices`), e.g. on sign-out.
    public func clearPushToken() async {
        if disposed { return }
        await ensureLoaded()
        let push = stored.pushToken
        let token = currentToken
        var next = stored
        next.pushToken = nil
        next.pushProvider = nil
        next.pushAppVersion = nil
        await persist(next)
        pushDirty = false
        pushRegisteredFor = nil
        if let push, let token {
            do {
                try await api.deleteDevice(token: token, pushToken: push)
            } catch {
                logger.warn("device removal failed: \(error)")
            }
        }
    }

    private func flushPush() async {
        guard let push = stored.pushToken, let token = currentToken, st.phase == .ready else { return }
        if !pushDirty && pushRegisteredFor == token { return }
        pushDirty = false
        pushRegisteredFor = token
        do {
            try await api.putDevice(token: token, device: DeviceRegistration(
                token: push,
                provider: PushProvider.tryParse(stored.pushProvider) ?? .fcm,
                platform: appInfo.os,
                installId: currentInstallId,
                locale: st.locale.code,
                appVersion: appInfo.version,
                osVersion: appInfo.osVersion,
                deviceModel: appInfo.deviceModel
            ))
        } catch {
            logger.warn("device registration failed: \(error)")
            pushRegisteredFor = nil
            pushDirty = true
        }
    }

    /// Largest sequence number the gateway accepts (32-bit signed).
    private static let maxSeq = Int(Int32.max)

    /// Whether older items exist before `timeline`: what the gateway says, or (older gateways) a guess from
    /// the first seq, which over-reports when the visitor's first items were hidden events.
    private static func olderExist(_ timeline: Timeline, _ server: Bool?) -> Bool {
        server ?? (!timeline.items.isEmpty && timeline.oldestSeq > 1)
    }
}

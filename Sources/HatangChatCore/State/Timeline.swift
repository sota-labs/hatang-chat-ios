import Foundation

/// The loaded window of a conversation.
public struct Timeline: Sendable, Hashable {
    /// Items in display order (oldest first).
    public var items: [TimelineItem]
    /// Older items exist before `oldestSeq`.
    public var hasMore: Bool
    /// Highest seq of a server item (local rows do not count).
    public var lastSeq: Int
    /// Lowest seq of a server item (0 when none).
    public var oldestSeq: Int

    public init(items: [TimelineItem] = [], hasMore: Bool = false, lastSeq: Int = 0, oldestSeq: Int = 0) {
        self.items = items
        self.hasMore = hasMore
        self.lastSeq = lastSeq
        self.oldestSeq = oldestSeq
    }

    /// Nothing loaded.
    public static let empty = Timeline()
}

private func ordered(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
    if a.seq != b.seq { return a.seq < b.seq }
    // A local row sits right after the server row that shares its seq.
    if a.isLocal != b.isLocal { return !a.isLocal }
    if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
    return a.id < b.id
}

/// Dedupe by id (the newer copy wins), keep seq order; `lastSeq` follows the newest server item and
/// `oldestSeq` the oldest one.
func mergeTimeline(_ cur: Timeline, _ items: [TimelineItem], hasMore: Bool? = nil) -> Timeline {
    var byId: [String: TimelineItem] = [:]
    for i in cur.items { byId[i.id] = i }
    for i in items { byId[i.id] = i }
    let merged = byId.values.sorted(by: ordered)
    var last = 0
    var oldest = 0
    for i in merged where !i.isLocal {
        if i.seq > last { last = i.seq }
        if oldest == 0 || i.seq < oldest { oldest = i.seq }
    }
    return Timeline(items: merged, hasMore: hasMore ?? cur.hasMore, lastSeq: last == 0 ? cur.lastSeq : last, oldestSeq: oldest)
}

/// Stamp `read_at` on the other side's messages up to `upTo`. `side` is who read: `agent` marks the
/// visitor's messages, `visitor` the team's. Returns `t` unchanged when nothing changed.
func applyRead(_ t: Timeline, side: String, upTo: Int, now: Date) -> Timeline {
    let mine = side == "agent"
    var changed = false
    let items = t.items.map { i -> TimelineItem in
        guard case .message(var m) = i, m.readAt == nil, m.seq <= upTo else { return i }
        let target = mine ? m.senderType == .visitor : m.senderType != .visitor
        guard target else { return i }
        changed = true
        m.readAt = now
        return .message(m)
    }
    guard changed else { return t }
    var out = t
    out.items = items
    return out
}

/// Drop the optimistic copy once the server echoes a message with the same client id.
func reconcilePending(_ pending: [PendingMessage], _ items: [TimelineItem]) -> [PendingMessage] {
    let echoed = Set(items.compactMap { $0.message?.clientId })
    if echoed.isEmpty { return pending }
    return pending.filter { !echoed.contains($0.clientId) }
}

/// Where to start a first `resume` so the latest window arrives: the server returns items *after* a seq.
func resumeFrom(_ conversationSeq: Int, window: Int = 150) -> Int {
    max(0, conversationSeq - window)
}

/// The highest seq among `items` (0 when empty); local rows do not count.
func maxSeq(_ items: [TimelineItem]) -> Int {
    max(0, items.filter { !$0.isLocal }.map(\.seq).max() ?? 0)
}

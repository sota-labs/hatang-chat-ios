import Foundation

/// Log severity.
public enum HatangLogLevel: Int, Sendable, Comparable, CaseIterable {
    /// Chatter useful while integrating.
    case debug
    /// Milestones (bootstrap, connect, session changes).
    case info
    /// Recoverable trouble (reconnects, ignored frames).
    case warn
    /// Failures the host should know about.
    case error

    public static func < (a: HatangLogLevel, b: HatangLogLevel) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .debug: return "debug"
        case .info: return "info"
        case .warn: return "warn"
        case .error: return "error"
        }
    }
}

/// Where the SDK writes its logs: every record at or above `minLevel` goes to `sink`. The default is
/// `silent`.
public struct HatangLogger: Sendable {
    /// Records below this level are dropped.
    public var minLevel: HatangLogLevel
    /// The sink.
    public var sink: @Sendable (HatangLogLevel, String) -> Void

    public init(minLevel: HatangLogLevel = .info, sink: @escaping @Sendable (HatangLogLevel, String) -> Void) {
        self.minLevel = minLevel
        self.sink = sink
    }

    /// Logs at `level`.
    public func log(_ level: HatangLogLevel, _ message: @autoclosure () -> String) {
        guard level >= minLevel else { return }
        sink(level, message())
    }

    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func warn(_ message: @autoclosure () -> String) { log(.warn, message()) }
    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }

    /// Drops everything.
    public static let silent = HatangLogger(minLevel: .error) { _, _ in }

    /// Prints to stdout with a `[hatang]` prefix.
    public static let console = HatangLogger(minLevel: .debug) { level, message in
        print("[hatang] \(level.name): \(message)")
    }
}

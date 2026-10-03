#if os(iOS)
import UIKit

/// Forwards app foreground/background changes to `onChange`, and runs `onActive` each time the app
/// becomes active (to show a chat that was requested while it was in the background).
@MainActor
final class AppLifecycle {
    private var tokens: [NSObjectProtocol] = []

    /// The app is active (not in the background and not inactive).
    var isActive: Bool { UIApplication.shared.applicationState == .active }

    /// The app is not in the background.
    var isForeground: Bool { UIApplication.shared.applicationState != .background }

    init(onChange: @escaping @MainActor (Bool) -> Void, onActive: @escaping @MainActor () -> Void) {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                onChange(true)
                onActive()
            }
        })
        tokens.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange(true) }
        })
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange(false) }
        })
    }

    func detach() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens = []
    }
}
#endif

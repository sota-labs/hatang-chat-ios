#if os(iOS)
import HatangChatCore
import Observation
import SwiftUI
import UIKit

/// Where the presented chat is: the inbox with conversations pushed on it, or a single conversation.
@MainActor
@Observable
final class ChatNavigator {
    enum Start: Equatable {
        case inbox
        case conversation(String?)
    }

    enum Route: Hashable {
        case conversation
    }

    var inboxRoot: Bool
    var path: [Route] = []
    /// Conversation to show at the root (nil: the active one).
    var requested: String?
    /// Bumped by every request so the screen re-opens even the same id.
    var serial = 0

    init(start: Start) {
        switch start {
        case .inbox:
            inboxRoot = true
        case .conversation(let id):
            inboxRoot = false
            requested = id
        }
    }

    /// Another `present` / notification while the chat is on screen.
    func go(to start: Start) {
        switch start {
        case .inbox:
            inboxRoot = true
            path = []
        case .conversation(let id):
            requested = id
            serial += 1
            if inboxRoot { path = [.conversation] }
        }
    }
}

/// Inbox or conversation at the root of a navigation stack; conversations opened from the inbox are
/// pushed, so back returns to the list.
struct ChatRootView: View {
    @State var navigator: ChatNavigator
    let model: HatangChatModel
    let onClose: (() -> Void)?
    var onOpenConversation: ((VisitorConversationDto) -> Void)?

    var body: some View {
        NavigationStack(path: $navigator.path) {
            Group {
                if navigator.inboxRoot {
                    InboxScreen(
                        model: model,
                        onOpen: { c in
                            navigator.requested = nil
                            model.run { await $0.openConversation(c.id, summary: c) }
                            if let onOpenConversation { onOpenConversation(c) } else { navigator.path = [.conversation] }
                        },
                        onNew: {
                            navigator.requested = nil
                            model.run { try await $0.openActive() }
                            navigator.path = [.conversation]
                        },
                        onClose: onClose
                    )
                } else {
                    ConversationScreen(model: model, conversationId: navigator.requested, openSerial: navigator.serial, onClose: onClose)
                }
            }
            .navigationDestination(for: ChatNavigator.Route.self) { _ in
                ConversationScreen(model: model, conversationId: navigator.requested, openSerial: navigator.serial)
            }
        }
    }
}

/// UIKit host for the chat (what `HatangChat.present` shows): the conversation, or the inbox with
/// conversations pushed on it.
public final class HatangChatViewController: UIHostingController<AnyView> {
    /// Called once the controller was dismissed.
    public var onDismiss: (() -> Void)?

    /// The conversation (the active one, or `conversationId`) with a close button.
    public convenience init(conversationId: String? = nil, model: HatangChatModel? = nil) {
        self.init(navigator: ChatNavigator(start: .conversation(conversationId)), model: model ?? HatangChat.model)
    }

    /// The inbox with a close button; tapping a conversation pushes it.
    public static func inbox(model: HatangChatModel? = nil) -> HatangChatViewController {
        HatangChatViewController(navigator: ChatNavigator(start: .inbox), model: model ?? HatangChat.model)
    }

    init(navigator: ChatNavigator, model: HatangChatModel) {
        super.init(rootView: AnyView(EmptyView()))
        let close: () -> Void = { [weak self] in self?.dismiss(animated: true) }
        rootView = AnyView(ChatRootView(navigator: navigator, model: model, onClose: close))
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onDismiss?() }
    }
}
#endif

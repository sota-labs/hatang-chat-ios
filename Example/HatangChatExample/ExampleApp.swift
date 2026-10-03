import HatangChat
import SwiftUI
import UserNotifications

@main
struct ExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var demo = Demo()

    var body: some Scene {
        WindowGroup {
            ContentView(demo: demo)
                .onOpenURL { demo.handle($0) }
                .onAppear { Automation.listen { demo.handle($0) } }
        }
    }
}

/// Push wiring: the APNs token goes to Hatang, and a tap on a Hatang notification opens its conversation.
/// (The example has no `aps-environment` entitlement, so registration fails harmlessly on the simulator.)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await HatangChat.setPushToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push registration failed: \(error.localizedDescription)")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Don't show a banner for a message the visitor is already looking at.
        let hatang = HatangChat.isHatangNotification(notification.request.content.userInfo)
        let onScreen = await MainActor.run { HatangChat.isPresented }
        return hatang && onScreen ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        HatangChat.handleNotification(response.notification.request.content.userInfo)
    }
}

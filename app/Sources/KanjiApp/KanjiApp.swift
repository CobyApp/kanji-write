import AppFeature
import ComposableArchitecture
import SwiftUI
import UserNotifications

@main
struct KanjiApp: App {
    @MainActor static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
    }
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(store: KanjiApp.store)
        }
    }
}

/// Routes a tapped reminder to the screen it is about (today's review).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["link"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run { _ = KanjiApp.store.send(.openLink(url)) }
    }

    /// Show the reminder even if the app happens to be open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

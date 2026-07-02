import ComposableArchitecture
import SharedModels
import UserNotifications

/// The learner's selected UI language, read from the same `@AppStorage` key the
/// views use, so the reminder is localized without threading state through TCA.
private var currentLanguage: AppLanguage {
    AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "ko") ?? .ko
}

/// Schedules a single repeating daily study reminder.
@DependencyClient
public struct NotificationClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Bool = { false }
    public var scheduleDailyReminder: @Sendable (_ hour: Int, _ minute: Int) async -> Void
    public var cancelReminders: @Sendable () async -> Void
}

private let reminderIdentifier = "daily-study-reminder"

extension NotificationClient: DependencyKey {
    public static let liveValue = NotificationClient(
        requestAuthorization: {
            let center = UNUserNotificationCenter.current()
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        },
        scheduleDailyReminder: { hour, minute in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
            let language = currentLanguage
            let content = UNMutableNotificationContent()
            content.title = L.notifTitle[language]
            content.body = L.notifBody[language]
            content.sound = .default
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: reminderIdentifier, content: content, trigger: trigger)
            try? await center.add(request)
        },
        cancelReminders: {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        }
    )
}

extension NotificationClient: TestDependencyKey {
    public static let testValue = NotificationClient()
}

extension DependencyValues {
    public var notificationClient: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}

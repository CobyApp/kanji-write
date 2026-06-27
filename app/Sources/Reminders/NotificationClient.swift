import ComposableArchitecture
import UserNotifications

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
            let content = UNMutableNotificationContent()
            content.title = "漢字の練習"
            content.body = "今日の漢字を書いて覚えましょう。"
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

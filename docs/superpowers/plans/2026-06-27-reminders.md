# Daily Reminder (Local Notifications) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or executing-plans. Checkbox steps.

**Goal:** A 設定 tab where the learner enables a daily study reminder at a chosen time, scheduling a repeating local notification.

**Architecture:** A `Reminders` module with a `NotificationClient` dependency (UNUserNotificationCenter-backed live) and a `ReminderFeature` that applies the enable/time setting via the client. `ReminderView` persists the setting via `@AppStorage` and re-applies on change. A 4th 設定 tab.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, UserNotifications, TCA 1.26. Build/test on iOS 26 iPad sim (UDID from `xcrun simctl list devices available | grep -i ipad`). Run from repo root; `git` from repo root. NOTE: notification authorization/delivery is device-only QA; only the feature logic (mocked client) is automated.

Test command shape:
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | tail -12`

---

## Task 1: NotificationClient (Reminders module)

**Files:**
- Modify: `app/Project.swift` (add `Reminders` + `RemindersTests` targets; scheme)
- Create: `app/Sources/Reminders/NotificationClient.swift`

- [ ] **Step 1: Add the module + test target to Project.swift**

In `app/Project.swift`, add (after `Review`, before `KanjiApp`) and add
`RemindersTests` to the scheme `testAction`:

```swift
        .target(
            name: "Reminders",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.reminders",
            deploymentTargets: iOS,
            sources: ["Sources/Reminders/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "RemindersTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.reminderstests",
            deploymentTargets: iOS,
            sources: ["Tests/RemindersTests/**"],
            dependencies: [.target(name: "Reminders")]
        ),
```

- [ ] **Step 2: Implement the client**

Create `app/Sources/Reminders/NotificationClient.swift`:

```swift
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
```

- [ ] **Step 3: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` (module compiles; no tests
yet for this thin system wrapper — it is device-QA).

- [ ] **Step 4: Commit**

```bash
git add app/Project.swift app/Sources/Reminders/NotificationClient.swift
git commit -m "feat(app): NotificationClient dependency (UNUserNotificationCenter daily reminder)"
```

---

## Task 2: ReminderFeature (TDD)

**Files:**
- Create: `app/Sources/Reminders/ReminderFeature.swift`
- Create: `app/Tests/RemindersTests/ReminderFeatureTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `app/Tests/RemindersTests/ReminderFeatureTests.swift`:

```swift
import ComposableArchitecture
import XCTest

@testable import Reminders

@MainActor
final class ReminderFeatureTests: XCTestCase {
    func testEnableRequestsAuthAndSchedules() async {
        let scheduled = LockIsolated<(Int, Int)?>(nil)
        let store = TestStore(initialState: ReminderFeature.State()) {
            ReminderFeature()
        } withDependencies: {
            $0.notificationClient.requestAuthorization = { true }
            $0.notificationClient.scheduleDailyReminder = { h, m in scheduled.setValue((h, m)) }
        }
        await store.send(.apply(enabled: true, hour: 20))
        await store.receive(.authorizationResult(true))
        XCTAssertEqual(scheduled.value?.0, 20)
        XCTAssertEqual(scheduled.value?.1, 0)
    }

    func testEnableDeniedSetsFlagAndDoesNotSchedule() async {
        let scheduled = LockIsolated(false)
        let store = TestStore(initialState: ReminderFeature.State()) {
            ReminderFeature()
        } withDependencies: {
            $0.notificationClient.requestAuthorization = { false }
            $0.notificationClient.scheduleDailyReminder = { _, _ in scheduled.setValue(true) }
        }
        await store.send(.apply(enabled: true, hour: 9))
        await store.receive(.authorizationResult(false)) { $0.authorizationDenied = true }
        XCTAssertFalse(scheduled.value)
    }

    func testDisableCancels() async {
        let cancelled = LockIsolated(false)
        let store = TestStore(initialState: ReminderFeature.State()) {
            ReminderFeature()
        } withDependencies: {
            $0.notificationClient.cancelReminders = { cancelled.setValue(true) }
        }
        await store.send(.apply(enabled: false, hour: 20))
        XCTAssertTrue(cancelled.value)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — `ReminderFeature` not found.

- [ ] **Step 3: Implement the reducer**

Create `app/Sources/Reminders/ReminderFeature.swift`:

```swift
import ComposableArchitecture

@Reducer
public struct ReminderFeature {
    @ObservableState
    public struct State: Equatable {
        public var authorizationDenied = false
        public init() {}
    }

    public enum Action: Equatable {
        case apply(enabled: Bool, hour: Int)
        case authorizationResult(Bool)
    }

    @Dependency(\.notificationClient) var notificationClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .apply(enabled, hour):
                guard enabled else {
                    return .run { _ in await notificationClient.cancelReminders() }
                }
                return .run { send in
                    let granted = await notificationClient.requestAuthorization()
                    if granted {
                        await notificationClient.scheduleDailyReminder(hour, 0)
                    }
                    await send(.authorizationResult(granted))
                }
            case let .authorizationResult(granted):
                state.authorizationDenied = !granted
                return .none
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **` (3 reminder tests pass).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/Reminders/ReminderFeature.swift app/Tests/RemindersTests/ReminderFeatureTests.swift
git commit -m "feat(app): ReminderFeature — enable/disable daily reminder (TDD)"
```

---

## Task 3: ReminderView + 設定 tab

**Files:**
- Modify: `app/Project.swift` (AppFeature depends on Reminders)
- Create: `app/Sources/Reminders/ReminderView.swift`
- Modify: `app/Sources/AppFeature/RootFeature.swift`
- Modify: `app/Sources/AppFeature/RootView.swift`

- [ ] **Step 1: Add the Reminders dependency to AppFeature**

In `app/Project.swift`, the `AppFeature` target `dependencies` — add
`.target(name: "Reminders")`.

- [ ] **Step 2: Implement the view**

Create `app/Sources/Reminders/ReminderView.swift`:

```swift
import ComposableArchitecture
import SwiftUI

public struct ReminderView: View {
    @Bindable public var store: StoreOf<ReminderFeature>
    @AppStorage("reminderEnabled") private var enabled = false
    @AppStorage("reminderHour") private var hour = 20

    public init(store: StoreOf<ReminderFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("リマインダー") {
                Toggle("毎日のリマインダー", isOn: $enabled)
                if enabled {
                    Picker("時刻", selection: $hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                }
                if store.authorizationDenied {
                    Text("通知が許可されていません。設定アプリで許可してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("設定")
        .task { store.send(.apply(enabled: enabled, hour: hour)) }
        .onChange(of: enabled) { _, newValue in
            store.send(.apply(enabled: newValue, hour: hour))
        }
        .onChange(of: hour) { _, newValue in
            store.send(.apply(enabled: enabled, hour: newValue))
        }
    }
}
```

- [ ] **Step 3: Add the reminder child to RootFeature**

In `app/Sources/AppFeature/RootFeature.swift`:

(a) add `import Reminders`.

(b) `State`: add `public var reminder = ReminderFeature.State()`; add a
`.settings` case to `Tab`:
`public enum Tab: Equatable { case browse, plan, review, settings }`.

(c) `Action`: add `case reminder(ReminderFeature.Action)`.

(d) `body`: add `Scope(state: \.reminder, action: \.reminder) { ReminderFeature() }`
and extend the no-op catch-all case to include `.reminder`:
`case .browse, .plan, .planPath, .review, .reminder:`.

- [ ] **Step 4: Add the 設定 tab to RootView**

In `app/Sources/AppFeature/RootView.swift`:

(a) add `import Reminders`.

(b) add a fourth tab inside the `TabView` (after the review tab):
```swift
            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(RootFeature.State.Tab.settings)
```

- [ ] **Step 5: Generate, build, run the full suite**

Run the test command. Expected: `** TEST SUCCEEDED **` — ReminderFeature tests
pass and the app builds with the 設定 tab.

- [ ] **Step 6: Commit**

```bash
git add app/Project.swift app/Sources/Reminders/ReminderView.swift app/Sources/AppFeature/RootFeature.swift app/Sources/AppFeature/RootView.swift
git commit -m "feat(app): 設定 tab — daily reminder toggle + time picker"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `NotificationClient` (spec §3) → Task 1; `ReminderFeature`
  (§3) → Task 2; `ReminderView` + 設定 tab (§3) → Task 3; tests (§4) → Task 2.
- **Device QA flagged:** the live `UNUserNotificationCenter` path (auth prompt,
  delivery) is not unit-tested; `ReminderFeature` is fully tested via a mocked
  `NotificationClient`. Task 1 has no unit test (thin system wrapper) — it is
  build-verified.
- **Persistence:** the toggle/time live in `@AppStorage`, re-applied to the
  system schedule on `.task` and on change, so the OS schedule stays in sync.
- **Type consistency:** `NotificationClient.{requestAuthorization,
  scheduleDailyReminder,cancelReminders}`, `ReminderFeature.Action`
  (`apply`/`authorizationResult`), and `Tab.settings` are used identically.
- **Nav:** browse/plan/review tabs untouched; only a new independent 設定 tab.

## Follow-on

Calendar-based plan pacing; notification deep-link into today's review; multiple
reminders; move the language picker into 設定.

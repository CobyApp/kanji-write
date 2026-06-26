# Daily Reminder (Local Notifications) — Design

Date: 2026-06-27
Status: Approved (delegated) — ready for implementation planning
Builds on: root TabView (merged).

## 1. Purpose

A daily study reminder: the learner enables a reminder at a chosen time, and the
app schedules a repeating local notification. (Calendar-based plan *pacing* is a
deferred follow-on — it would rework the study plan's progression model; this
slice is the reminders half of follow-on #6.)

## 2. Scope & Non-Goals

In scope:
- A `NotificationClient` dependency (request authorization, schedule a daily
  repeating reminder, cancel) with a `UNUserNotificationCenter`-backed live impl.
- A `ReminderFeature` that applies the enable/time setting via the client.
- A `ReminderView` (toggle + time picker), persisted via `@AppStorage`.
- A 設定 tab in the root TabView.

Non-goals (follow-on):
- Calendar-based plan progression (the plan stays pace-based).
- Notification deep-links/actions; multiple reminders; quiet hours.
- **Device dependency:** authorization prompts and delivery are only verifiable
  on a real device — automated tests cover the feature logic via a mocked
  client; the live `UNUserNotificationCenter` path is manual/device QA.

## 3. Components

- **`NotificationClient`** (`@DependencyClient`, new `Reminders` module):
  - `requestAuthorization: @Sendable () async -> Bool`
  - `scheduleDailyReminder: @Sendable (_ hour: Int, _ minute: Int) async -> Void`
  - `cancelReminders: @Sendable () async -> Void`
  `liveValue` wraps `UNUserNotificationCenter.current()`: requests
  `.alert/.sound` authorization; schedules a `UNCalendarNotificationTrigger`
  (repeating, at hour:minute) with a fixed identifier; cancels by removing that
  identifier.
- **`ReminderFeature`** (`@Reducer`): `State { authorizationDenied: Bool }`
  (for optional UI feedback); `Action { apply(enabled: Bool, hour: Int) }`.
  `apply(true, hour)` → request authorization; if granted, schedule at
  `hour:00`, else set `authorizationDenied`. `apply(false, _)` → cancel.
- **`ReminderView`**: `@AppStorage("reminderEnabled") Bool = false` and
  `@AppStorage("reminderHour") Int = 20`; a `Toggle` and (when enabled) an
  hour `Picker`. `.onChange` of either and `.task` (on appear) send
  `.apply(enabled, hour)` so the system schedule re-syncs with the persisted
  setting. Shows a note if `authorizationDenied`.
- **Root nav**: `RootFeature` adds `reminder: ReminderFeature.State` and a
  `.settings` tab; `RootView` adds a 設定 tab (gearshape icon).

## 4. Testing

- **`ReminderFeature`** (`TestStore`, mocked `NotificationClient`):
  `apply(enabled: true, hour: 20)` with granted auth → `requestAuthorization`
  then `scheduleDailyReminder(20, 0)` invoked (verified via `LockIsolated`);
  denied auth → `authorizationDenied = true` and no schedule; `apply(false, _)`
  → `cancelReminders` invoked.
- Build verification green. The live notification path (permission prompt,
  delivery) is manual device QA — not automated.

## 5. Build order

1. `NotificationClient` dependency (interface + `UNUserNotificationCenter` live).
2. `ReminderFeature` (TDD with a mocked client).
3. `ReminderView` + 設定 tab in `RootFeature`/`RootView` (build-verified).

## 6. Follow-on

Calendar-based plan pacing; notification deep-link into today's review; multiple
/ smarter reminders; move the language picker into 設定.

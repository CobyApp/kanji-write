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

import ComposableArchitecture
import Review

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
        case resetProgress   // clears kanji + word SRS records and the wordbook
    }

    @Dependency(\.notificationClient) var notificationClient
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.wordReviewStore) var wordReviewStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .resetProgress:
                return .run { _ in
                    await reviewStore.saveRecords([])
                    await wordReviewStore.saveRecords([])
                }
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

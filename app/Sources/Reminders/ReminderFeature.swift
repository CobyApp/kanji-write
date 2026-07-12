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
        case resetProgress   // clears kanji + word SRS records, the wordbook, and quiz history
    }

    @Dependency(\.notificationClient) var notificationClient
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.wordReviewStore) var wordReviewStore
    @Dependency(\.quizStore) var quizStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .resetProgress:
                return .run { _ in
                    await reviewStore.saveRecords([])
                    await wordReviewStore.saveRecords([])
                    // Progress reset also wipes quiz history so quizzes start fresh.
                    await quizStore.save([])
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

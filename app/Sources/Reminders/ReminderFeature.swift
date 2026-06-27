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

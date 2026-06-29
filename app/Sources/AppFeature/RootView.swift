import ComposableArchitecture
import DesignSystem
import KanjiDetail
import Reminders
import Review
import SharedModels
import StudyPlan
import SwiftUI
import WritingCanvas

public struct RootView: View {
    @Bindable public var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<RootFeature>) {
        self.store = store
    }

    public var body: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            AppView(store: store.scope(state: \.browse, action: \.browse))
                .tabItem { Label("一覧", systemImage: "list.bullet") }
                .tag(RootFeature.State.Tab.browse)

            NavigationStack(
                path: $store.scope(state: \.planPath, action: \.planPath)
            ) {
                StudyHubView(
                    reviewStore: store.scope(state: \.review, action: \.review)
                )
            } destination: { store in
                switch store.case {
                case let .detail(store):
                    KanjiDetailView(store: store)
                case let .writing(store):
                    KanjiWritingView(store: store)
                }
            }
            .tabItem { Label("学習", systemImage: "pencil.and.outline") }
            .tag(RootFeature.State.Tab.study)

            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(RootFeature.State.Tab.settings)
        }
        .tint(Palette.accent)
        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
    }
}

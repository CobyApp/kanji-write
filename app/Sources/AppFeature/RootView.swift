import ComposableArchitecture
import KanjiDetail
import StudyPlan
import SwiftUI
import WritingCanvas

public struct RootView: View {
    @Bindable public var store: StoreOf<RootFeature>

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
                StudyPlanView(store: store.scope(state: \.plan, action: \.plan))
            } destination: { store in
                switch store.case {
                case let .detail(store):
                    KanjiDetailView(store: store)
                case let .writing(store):
                    KanjiWritingView(store: store)
                }
            }
            .tabItem { Label("プラン", systemImage: "calendar") }
            .tag(RootFeature.State.Tab.plan)
        }
    }
}

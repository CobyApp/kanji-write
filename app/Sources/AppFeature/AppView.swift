import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import SwiftUI
import WritingCanvas

public struct AppView: View {
    @Bindable public var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            KanjiListView(
                store: store.scope(state: \.kanjiList, action: \.kanjiList)
            )
        } destination: { store in
            switch store.case {
            case let .detail(store):
                KanjiDetailView(store: store)
            case let .writing(store):
                KanjiWritingView(store: store)
            }
        }
    }
}

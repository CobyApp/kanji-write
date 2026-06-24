import ComposableArchitecture
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
            KanjiWritingView(store: store)
        }
    }
}

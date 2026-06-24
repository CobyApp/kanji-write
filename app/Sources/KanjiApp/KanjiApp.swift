import AppFeature
import ComposableArchitecture
import KanjiListFeature
import SwiftUI

@main
struct KanjiApp: App {
    @MainActor static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            KanjiListView(
                store: KanjiApp.store.scope(state: \.kanjiList, action: \.kanjiList)
            )
        }
    }
}

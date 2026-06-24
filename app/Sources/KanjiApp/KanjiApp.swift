import AppFeature
import ComposableArchitecture
import SwiftUI

@main
struct KanjiApp: App {
    @MainActor static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: KanjiApp.store)
        }
    }
}

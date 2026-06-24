import ComposableArchitecture
import SharedModels
import SwiftUI

public struct KanjiListView: View {
    @Bindable public var store: StoreOf<KanjiListFeature>

    public init(store: StoreOf<KanjiListFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView()
                } else if let error = store.loadError {
                    ContentUnavailableView(
                        "読み込み失敗",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    List(store.kanji) { kanji in
                        HStack(spacing: 16) {
                            Text(kanji.literal)
                                .font(.largeTitle)
                            VStack(alignment: .leading) {
                                Text(kanji.onReadings.joined(separator: "、"))
                                Text(kanji.kunReadings.joined(separator: "、"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("漢字")
            .task { store.send(.onAppear) }
        }
    }
}

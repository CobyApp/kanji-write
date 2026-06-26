import ComposableArchitecture
import SwiftUI

public struct ReviewView: View {
    @Bindable public var store: StoreOf<ReviewFeature>

    public init(store: StoreOf<ReviewFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.dueKanji.isEmpty {
                ContentUnavailableView("今日の復習はありません",
                                       systemImage: "checkmark.circle")
            } else {
                List(store.dueKanji) { kanji in
                    HStack {
                        Text(kanji.literal).font(.largeTitle)
                        Spacer()
                        Button("もう一度") {
                            store.send(.grade(kanjiID: kanji.id, correct: false))
                        }
                        .buttonStyle(.bordered)
                        Button("正解") {
                            store.send(.grade(kanjiID: kanji.id, correct: true))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle("復習")
        .task { store.send(.onAppear) }
    }
}

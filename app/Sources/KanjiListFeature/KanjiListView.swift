import ComposableArchitecture
import SharedModels
import SwiftUI

public struct KanjiListView: View {
    @Bindable public var store: StoreOf<KanjiListFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<KanjiListFeature>) {
        self.store = store
    }

    public var body: some View {
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
                    Button {
                        store.send(.kanjiTapped(kanji))
                    } label: {
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
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("漢字")
        .toolbar {
            Menu {
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
            } label: {
                Image(systemName: "globe")
            }
        }
        .task { store.send(.onAppear) }
    }
}

import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct ReviewView: View {
    @Bindable public var store: StoreOf<ReviewFeature>

    public init(store: StoreOf<ReviewFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if store.dueKanji.isEmpty {
                ContentUnavailableView("今日の復習はありません",
                                       systemImage: "checkmark.circle")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(store.dueKanji.enumerated()), id: \.element.id) { index, kanji in
                            row(kanji, tint: Palette.tint(index))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("復習")
        .task { store.send(.onAppear) }
    }

    private func row(_ kanji: Kanji, tint: (soft: Color, accent: Color)) -> some View {
        HStack(spacing: 14) {
            PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent)
            Spacer()
            Button("もう一度") {
                store.send(.grade(kanjiID: kanji.id, correct: false))
            }
            .font(.kawaii(14, weight: .bold))
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Palette.card).clipShape(Capsule())
            .overlay(Capsule().stroke(Palette.inkSoft.opacity(0.3), lineWidth: 1))

            Button("正解") {
                store.send(.grade(kanjiID: kanji.id, correct: true))
            }
            .font(.kawaii(14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(tint.accent).clipShape(Capsule())
        }
        .roundedCard()
    }
}

import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

public struct PracticeView: View {
    @Bindable public var store: StoreOf<PracticeFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<PracticeFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    pickerSection
                    if store.selected != nil {
                        notebookCard
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(L.practice[appLanguage])
        .toolbar {
            Button(store.showGuide ? L.hideGuide[appLanguage] : L.showGuide[appLanguage]) {
                store.send(.toggleGuide)
            }
            Button(L.clearWriting[appLanguage]) { store.send(.clearAll) }
        }
        .task { store.send(.onAppear) }
    }

    // MARK: - Kanji picker (horizontal strip of pastel tiles)

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.pickToPractice[appLanguage], accent: Palette.pink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.kanji.enumerated()), id: \.element.id) { index, kanji in
                        let tint = Palette.tint(index)
                        Button { store.send(.kanjiSelected(kanji)) } label: {
                            PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                       size: 56, fontSize: 30)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(store.selected?.id == kanji.id ? Palette.accent : Color.clear,
                                                lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .roundedCard()
    }

    // MARK: - Notebook grid (responsive, fills width)

    private var notebookCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = store.selected {
                HStack(spacing: 10) {
                    PastelTile(selected.literal, soft: Palette.pinkSoft, accent: Palette.pink,
                               size: 44, fontSize: 26)
                    Text(L.practicePrompt[appLanguage])
                        .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
            }
            TracingGrid(glyph: store.selected?.literal ?? "", paths: store.strokePaths,
                        showGuide: store.showGuide, clearToken: store.clearToken, cellCount: 12)
        }
        .roundedCard()
    }
}

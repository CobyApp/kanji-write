import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

public struct PracticeView: View {
    @Bindable public var store: StoreOf<PracticeFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var vSize

    /// A 10-cell (5×2 or 2×5) notebook filling the width: landscape / iPad → 5
    /// columns × 2 rows; iPhone portrait → 2 columns × 5 rows.
    private var traceColumns: Int {
        if sizeClass == .regular { return 5 }
        return vSize == .compact ? 5 : 2
    }

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(store.showGuide ? L.hideGuide[appLanguage] : L.showGuide[appLanguage]) {
                store.send(.toggleGuide)
            }
            Button(L.clearWriting[appLanguage]) { store.send(.clearAll) }
        }
        .task { store.send(.onAppear) }
    }

    // MARK: - Kanji picker (horizontal strip of pastel tiles)

    private var levelBinding: Binding<String> {
        Binding(get: { store.level }, set: { store.send(.levelSelected($0)) })
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.pickToPractice[appLanguage], accent: Palette.pink)
            Picker(L.level[appLanguage], selection: levelBinding) {
                ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.levelKanji.enumerated()), id: \.element.id) { index, kanji in
                        let tint = Palette.tint(index)
                        Button { store.send(.kanjiSelected(kanji)) } label: {
                            PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                       size: 56, fontSize: 30)
                                // strokeBorder draws inside the tile bounds so the
                                // selection ring is never clipped by the card/scroll.
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(store.selected?.id == kanji.id ? Palette.accent : Color.clear,
                                                      lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 3)
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
                        showGuide: store.showGuide, clearToken: store.clearToken,
                        cellCount: 10, columns: traceColumns)
        }
        .roundedCard()
    }
}

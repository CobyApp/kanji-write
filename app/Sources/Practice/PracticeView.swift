import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

/// The kanji's meaning for the selected language, falling back deterministically.
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

public struct PracticeView: View {
    @Bindable public var store: StoreOf<PracticeFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    /// The last-practiced kanji id, restored on next open (0 = none yet).
    @AppStorage("practiceKanjiID") private var savedKanjiID = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var vSize

    /// A responsive notebook filling the width: landscape / iPad → 5 columns;
    /// iPhone portrait → 2 columns.
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
        }
        .task { store.send(.onAppear(selectedID: savedKanjiID == 0 ? nil : savedKanjiID)) }
        .onChange(of: store.selected?.id) { _, id in
            if let id { savedKanjiID = id }  // remember the selection
        }
    }

    // MARK: - Kanji picker (horizontal strip of pastel tiles, auto-focused)

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
            ScrollViewReader { proxy in
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
                            .id(kanji.id)
                        }
                    }
                    .padding(.vertical, 3)
                }
                // Auto-scroll the strip to the selected kanji (restore / change).
                .task(id: store.selected?.id) {
                    guard let id = store.selected?.id else { return }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    withAnimation(.easeInOut) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .roundedCard()
    }

    // MARK: - Notebook grid (responsive, fills width) + actions

    private var notebookCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = store.selected {
                infoRow(selected)
            }
            TracingGrid(glyph: store.selected?.literal ?? "", paths: store.strokePaths,
                        showGuide: store.showGuide, clearToken: store.clearToken,
                        cellCount: store.cellCount, columns: traceColumns)
            HStack(spacing: 12) {
                actionButton(L.clearWriting[appLanguage], "eraser", Palette.pink) {
                    store.send(.clearAll)
                }
                actionButton(L.addCells[appLanguage], "plus", Palette.mint) {
                    store.send(.addCells)
                }
            }
        }
        .roundedCard()
    }

    /// The selected kanji's meaning (뜻음) + readings (음/훈) with a speaker.
    /// The glyph tile is a fixed size matching the full info block (meaning +
    /// on + kun) so it stays the same across kanji, even when a reading is absent.
    private func infoRow(_ kanji: Kanji) -> some View {
        // Fixed height = meaning line + on line + kun line + spacings.
        let tileSize: CGFloat = 84
        return HStack(alignment: .center, spacing: 14) {
            PastelTile(kanji.literal, soft: Palette.pinkSoft, accent: Palette.pink,
                       size: tileSize, fontSize: tileSize * 0.6)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if let meaning = localizedGloss(store.glosses, appLanguage), !meaning.isEmpty {
                        Text(meaning)
                            .font(.kawaii(19, weight: .bold, language: appLanguage))
                            .foregroundStyle(Palette.ink)
                    }
                    SpeakButton(kanji.literal)
                }
                if !kanji.onReadings.isEmpty {
                    readingLine(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
                }
                if !kanji.kunReadings.isEmpty {
                    readingLine(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
                }
            }
            Spacer(minLength: 0)
        }
        // Reserve the full-info height so the tile size (and row) never changes.
        .frame(minHeight: tileSize, alignment: .center)
    }

    private func readingLine(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.kawaii(12, weight: .bold)).foregroundStyle(accent)
                .frame(width: 26, alignment: .leading)
            Text(readings.joined(separator: "、"))
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
    }

    private func actionButton(_ label: String, _ icon: String, _ color: Color,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.kawaii(14, weight: .bold)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(color.opacity(0.14)).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }
}

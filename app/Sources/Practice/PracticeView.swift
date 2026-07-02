import ComposableArchitecture
import DesignSystem
import PencilKit
import SharedModels
import SwiftUI
import WritingCanvas

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled into the cell.
private struct PracticeGuideView: View {
    /// KanjiVG strokes are authored in a fixed 109x109 coordinate space.
    private static let viewBoxSize: CGFloat = 109.0
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewBoxSize
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Palette.inkSoft.opacity(0.28), lineWidth: 2.5)
            }
        }
    }
}

/// A single square write cell: an independent Pencil canvas over a faint guide,
/// with a light center cross like squared practice paper (原稿用紙).
private struct PracticeCell: View {
    let paths: [String]
    let showGuide: Bool
    /// When this token changes, the cell wipes its drawing (clear-all / switch).
    let clearToken: Int
    @State private var drawing = PKDrawing()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
            // Faint center guide lines, like squared practice paper.
            GeometryReader { geo in
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Palette.pinkSoft, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if showGuide {
                PracticeGuideView(paths: paths)
            }
            PencilCanvasView(drawing: $drawing)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.pink.opacity(0.3), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: clearToken) { _, _ in drawing = PKDrawing() }
    }
}

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
                            PastelTile(
                                kanji.literal,
                                soft: tint.soft,
                                accent: tint.accent,
                                size: 56, fontSize: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        store.selected?.id == kanji.id
                                            ? Palette.accent : Color.clear,
                                        lineWidth: 3)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .roundedCard()
    }

    // MARK: - Notebook grid

    private var notebookCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = store.selected {
                HStack(spacing: 10) {
                    PastelTile(
                        selected.literal, soft: Palette.pinkSoft, accent: Palette.pink,
                        size: 44, fontSize: 26)
                    Text(L.practicePrompt[appLanguage])
                        .font(.kawaii(14, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            GeometryReader { geo in
                let columns = PracticeGrid.columnCount(forWidth: geo.size.width)
                let grid = Array(
                    repeating: GridItem(.flexible(), spacing: 12), count: columns)
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(0..<PracticeGrid.cellCount, id: \.self) { _ in
                        PracticeCell(
                            paths: store.strokePaths,
                            showGuide: store.showGuide,
                            clearToken: store.clearToken)
                    }
                }
            }
            .frame(minHeight: gridHeight)
        }
        .roundedCard()
    }

    /// Approximate height so the LazyVGrid inside a ScrollView lays out fully.
    /// Uses the screen width as a stable estimate of the available card width.
    private var gridHeight: CGFloat {
        let width = UIScreen.main.bounds.width - 64  // page + card padding
        let columns = PracticeGrid.columnCount(forWidth: width)
        let rows = PracticeGrid.rowCount(columns: columns)
        let cell = (width - CGFloat(columns - 1) * 12) / CGFloat(columns)
        return CGFloat(rows) * cell + CGFloat(rows - 1) * 12
    }
}

import DesignSystem
import PencilKit
import SharedModels
import SwiftUI

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled into a cell.
private struct TraceGuide: View {
    private static let viewBoxSize: CGFloat = 109.0
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewBoxSize
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Palette.inkSoft.opacity(0.4), lineWidth: 3)
            }
        }
    }
}

/// One square write cell: an independent Pencil canvas over a faint character
/// template (so the cell is never an empty box) plus the stroke-order guide,
/// with squared-paper center lines (原稿用紙). Wipes when `clearToken` changes.
private struct TraceCell: View {
    let glyph: String
    let paths: [String]
    let showGuide: Bool
    let clearToken: Int
    @State private var drawing = PKDrawing()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card)
            GeometryReader { geo in
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Palette.pinkSoft, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            // Faint character template — always shown so a cell is never a blank
            // box; the learner traces right over it.
            Text(glyph)
                .font(.system(size: 500))
                .minimumScaleFactor(0.01)
                .lineLimit(1)
                .foregroundStyle(Palette.ink.opacity(0.14))
                .padding(8)
            if showGuide && !paths.isEmpty { TraceGuide(paths: paths) }
            PencilCanvasView(drawing: $drawing)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Palette.pink.opacity(0.3), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: clearToken) { _, _ in drawing = PKDrawing() }
    }
}

/// A responsive 한자노트 grid: small square write cells that auto-fill the
/// available width (more columns on a wide iPad, fewer when narrow). Every cell
/// shows the character faintly as a tracing template. Reused by the Practice
/// notebook and the Worksheet "write" step.
public struct TracingGrid: View {
    let glyph: String
    let paths: [String]
    let showGuide: Bool
    let clearToken: Int
    let cellCount: Int
    let minCell: CGFloat
    /// When set, lay out exactly this many equal columns (e.g. 5 → a 5×2 sheet
    /// for 10 cells). When nil, columns auto-fill to `minCell`.
    let columns: Int?

    public init(
        glyph: String, paths: [String], showGuide: Bool = true, clearToken: Int = 0,
        cellCount: Int = 12, minCell: CGFloat = 108, columns: Int? = nil
    ) {
        self.glyph = glyph
        self.paths = paths
        self.showGuide = showGuide
        self.clearToken = clearToken
        self.cellCount = cellCount
        self.minCell = minCell
        self.columns = columns
    }

    private var gridColumns: [GridItem] {
        if let columns {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, columns))
        }
        return [GridItem(.adaptive(minimum: minCell), spacing: 12)]
    }

    public var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(0..<cellCount, id: \.self) { _ in
                TraceCell(glyph: glyph, paths: paths, showGuide: showGuide, clearToken: clearToken)
            }
        }
    }
}

/// A horizontal row of trace cells — one per character of a word — so the
/// learner traces the whole word left-to-right. Kanji show their stroke-order
/// guide; kana show just the faint glyph template.
public struct WordTracingGrid: View {
    public struct Char: Equatable, Identifiable {
        public let id: Int          // position in the surface (stable, unique)
        public let glyph: String
        public let paths: [String]  // KanjiVG guide for kanji; empty for kana
        public init(id: Int, glyph: String, paths: [String]) {
            self.id = id
            self.glyph = glyph
            self.paths = paths
        }
    }

    let characters: [Char]
    let showGuide: Bool
    let clearToken: Int
    let cell: CGFloat

    public init(
        characters: [Char], showGuide: Bool = true, clearToken: Int = 0, cell: CGFloat = 120
    ) {
        self.characters = characters
        self.showGuide = showGuide
        self.clearToken = clearToken
        self.cell = cell
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(characters) { char in
                    TraceCell(glyph: char.glyph, paths: char.paths,
                              showGuide: showGuide, clearToken: clearToken)
                        .frame(width: cell, height: cell)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

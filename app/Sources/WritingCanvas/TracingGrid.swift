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
                    .stroke(Palette.inkSoft.opacity(0.28), lineWidth: 2.5)
            }
        }
    }
}

/// One square write cell: an independent Pencil canvas over a faint stroke guide,
/// with squared-paper center lines (原稿用紙). Wipes when `clearToken` changes.
private struct TraceCell: View {
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
            if showGuide { TraceGuide(paths: paths) }
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
/// available width (more columns on a wide iPad, fewer when narrow). Reused by
/// the Practice notebook and the Worksheet "write" step.
public struct TracingGrid: View {
    let paths: [String]
    let showGuide: Bool
    let clearToken: Int
    let cellCount: Int
    let minCell: CGFloat

    public init(
        paths: [String], showGuide: Bool = true, clearToken: Int = 0,
        cellCount: Int = 12, minCell: CGFloat = 108
    ) {
        self.paths = paths
        self.showGuide = showGuide
        self.clearToken = clearToken
        self.cellCount = cellCount
        self.minCell = minCell
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minCell), spacing: 12)], spacing: 12
        ) {
            ForEach(0..<cellCount, id: \.self) { _ in
                TraceCell(paths: paths, showGuide: showGuide, clearToken: clearToken)
            }
        }
    }
}

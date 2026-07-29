import DesignSystem
import SwiftUI

/// KanjiVG authors every path against a 109×109 box.
private let markedGlyphViewBox: CGFloat = 109.0

/// One stroke of a KanjiVG glyph, scaled to fill whatever rect it is given.
private struct SingleStroke: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / markedGlyphViewBox
        return SVGPath.path(from: SVGPath.parse(d))
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// A kanji drawn from its strokes with exactly one of them picked out.
///
/// 筆順 asks where in the writing order *this* stroke comes, which cannot be put
/// into words — the stroke has to be pointed at. The rest of the glyph stays
/// visible but faint: the question is about one stroke's place in the whole, so
/// hiding the others would take away the context that makes it answerable.
public struct MarkedStrokeGlyph: View {
    private let paths: [String]
    private let marked: Int

    public init(paths: [String], marked: Int) {
        self.paths = paths
        self.marked = marked
    }

    public var body: some View {
        ZStack {
            ForEach(Array(paths.enumerated()), id: \.offset) { index, d in
                SingleStroke(d: d)
                    .stroke(
                        index == marked ? Palette.pink : Palette.ink.opacity(0.16),
                        style: StrokeStyle(lineWidth: index == marked ? 6 : 4,
                                           lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

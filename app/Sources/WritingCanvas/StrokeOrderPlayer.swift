import SwiftUI

/// Fraction (0...1) of stroke `index` drawn at overall `progress`
/// (progress ranges 0...strokeCount).
func strokeFraction(progress: Double, index: Int) -> Double {
    min(max(progress - Double(index), 0), 1)
}

/// Draws KanjiVG strokes progressively: each stroke completes before the next
/// begins, driven by `progress` (0...strokeCount).
private struct StrokesShape: Shape {
    var progress: Double
    let paths: [String]

    /// KanjiVG strokes are authored in a fixed 109x109 coordinate space.
    private static let viewBoxSize: CGFloat = 109.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.viewBoxSize
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        var combined = Path()
        for (index, d) in paths.enumerated() {
            let fraction = strokeFraction(progress: progress, index: index)
            if fraction <= 0 { continue }
            let full = SVGPath.path(from: SVGPath.parse(d)).applying(transform)
            combined.addPath(fraction >= 1 ? full : full.trimmedPath(from: 0, to: CGFloat(fraction)))
        }
        return combined
    }
}

/// An animated stroke-order display with a replay button.
public struct StrokeOrderPlayer: View {
    private let paths: [String]
    @State private var progress: Double

    public init(paths: [String]) {
        self.paths = paths
        // Start showing the full glyph.
        _progress = State(initialValue: Double(paths.count))
    }

    public var body: some View {
        VStack(spacing: 12) {
            StrokesShape(progress: progress, paths: paths)
                .stroke(Color.primary,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)
                .background(Color(.secondarySystemBackground))
            Button {
                progress = 0
                withAnimation(.easeInOut(duration: Double(paths.count) * 0.5)) {
                    progress = Double(paths.count)
                }
            } label: {
                Label("再生", systemImage: "play.circle")
            }
        }
    }
}

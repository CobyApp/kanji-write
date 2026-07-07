import DesignSystem
import SharedModels
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

/// An animated stroke-order display: strokes draw on in order, auto-playing once
/// on appear, with a replay button. Kawaii-styled and localized.
public struct StrokeOrderPlayer: View {
    private let paths: [String]
    private let size: CGFloat
    @State private var progress: Double
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(paths: [String], size: CGFloat = 200) {
        self.paths = paths
        self.size = size
        // Start on the full glyph; auto-plays from 0 on appear.
        _progress = State(initialValue: Double(paths.count))
    }

    private var duration: Double { max(1.2, Double(paths.count) * 0.9) }

    private func play() {
        progress = 0
        withAnimation(.easeInOut(duration: duration)) { progress = Double(paths.count) }
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Faint full glyph as a target behind the animated strokes.
                StrokesShape(progress: Double(paths.count), paths: paths)
                    .stroke(Palette.inkSoft.opacity(0.25),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                StrokesShape(progress: progress, paths: paths)
                    .stroke(Palette.ink,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
            .background(Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.mint.opacity(0.35), lineWidth: 1.5))

            Button(action: play) {
                Label(L.play[appLanguage], systemImage: "play.circle.fill")
                    .font(.kawaii(14, weight: .bold)).foregroundStyle(Palette.mint)
            }
            .buttonStyle(.plain)
        }
        .onAppear(perform: play)
    }
}

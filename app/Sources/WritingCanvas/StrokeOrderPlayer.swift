import DesignSystem
import SharedModels
import SwiftUI

/// Fraction (0...1) of stroke `index` drawn at overall `progress`
/// (progress ranges 0...strokeCount).
func strokeFraction(progress: Double, index: Int) -> Double {
    min(max(progress - Double(index), 0), 1)
}

/// KanjiVG strokes are authored in a fixed 109x109 coordinate space.
private let kanjiViewBox: CGFloat = 109.0

/// One KanjiVG stroke, trimmed to its share of the overall `progress` so strokes
/// draw on one after another.
private struct SingleStroke: Shape {
    var progress: Double
    let index: Int
    let d: String

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = strokeFraction(progress: progress, index: index)
        guard fraction > 0 else { return Path() }
        let scale = min(rect.width, rect.height) / kanjiViewBox
        let full = SVGPath.path(from: SVGPath.parse(d)).applying(CGAffineTransform(scaleX: scale, y: scale))
        return fraction >= 1 ? full : full.trimmedPath(from: 0, to: CGFloat(fraction))
    }
}

/// An animated stroke-order display: each stroke draws on in order in its own
/// pastel color, with a stroke-number badge at its start, a soft bounce as it
/// finishes, auto-playing once on appear, and a replay button.
public struct StrokeOrderPlayer: View {
    private let paths: [String]
    private let size: CGFloat
    private let isActive: Bool
    @State private var progress: Double
    @State private var bounce = false
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    /// Candy palette cycled across strokes.
    private static let strokeColors: [Color] = [
        Palette.pink, Palette.mint, Palette.sky, Palette.lavender, Palette.butter,
    ]
    private func color(_ index: Int) -> Color {
        Self.strokeColors[index % Self.strokeColors.count]
    }

    /// `isActive` gates the auto-play: pass `false` while the player is off-screen
    /// (e.g. an unselected page in a card deck) and flip it to `true` when it
    /// becomes visible to replay the animation from the start.
    public init(paths: [String], size: CGFloat = 200, isActive: Bool = true) {
        self.paths = paths
        self.size = size
        self.isActive = isActive
        // Start on the full glyph; auto-plays from 0 when active.
        _progress = State(initialValue: Double(paths.count))
    }

    private var duration: Double { max(1.2, Double(paths.count) * 0.9) }
    private var lineWidth: CGFloat { max(7, size * 0.045) }

    private func play() {
        bounce = false
        progress = 0
        withAnimation(.easeInOut(duration: duration)) {
            progress = Double(paths.count)
        } completion: {
            // A little settle-pop once the glyph is complete.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { bounce = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.14)) { bounce = false }
        }
    }

    /// The scaled start point of a stroke (where its number badge sits).
    private func startPoint(_ d: String) -> CGPoint? {
        let scale = size / kanjiViewBox
        let path = SVGPath.path(from: SVGPath.parse(d))
            .applying(CGAffineTransform(scaleX: scale, y: scale))
        var point: CGPoint?
        path.cgPath.applyWithBlock { element in
            if point == nil, element.pointee.type == .moveToPoint {
                point = element.pointee.points[0]
            }
        }
        return point
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Faint full glyph as a target behind the animated strokes.
                ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                    SingleStroke(progress: Double(paths.count), index: 0, d: d)
                        .stroke(Palette.inkSoft.opacity(0.16),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                // Colored strokes drawing on in order.
                ForEach(Array(paths.enumerated()), id: \.offset) { index, d in
                    SingleStroke(progress: progress, index: index, d: d)
                        .stroke(color(index),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                // Stroke-order numbers, appearing as each stroke starts.
                ForEach(Array(paths.enumerated()), id: \.offset) { index, d in
                    if strokeFraction(progress: progress, index: index) > 0, let pt = startPoint(d) {
                        Text("\(index + 1)")
                            .font(.system(size: size * 0.07, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.12, height: size * 0.12)
                            .background(color(index), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                            .position(x: pt.x, y: pt.y)
                    }
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(bounce ? 1.06 : 1)
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
        .onAppear { if isActive { play() } }
        .onChange(of: isActive) { _, active in if active { play() } }
    }
}

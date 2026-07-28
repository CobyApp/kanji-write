import SwiftUI

/// A single track with two handles, for picking a span rather than a point.
///
/// Two stacked `Slider`s said "from" and "to" but drew the range as two
/// unrelated positions; the thing being chosen is one interval, so it reads
/// better as one bar with the selected stretch filled in. The handles also
/// cannot cross — the low one stops at the high one and vice versa, so the range
/// can never invert and the caller never has to repair it.
public struct RangeSlider: View {
    @Binding private var low: Int
    @Binding private var high: Int
    private let bounds: ClosedRange<Int>
    private let accent: Color
    /// Which handle the current drag owns, so a drag that passes the other one
    /// does not hand over control mid-gesture.
    @State private var dragging: Handle?

    private enum Handle { case low, high }

    private let trackHeight: CGFloat = 8
    private let thumb: CGFloat = 30

    public init(low: Binding<Int>, high: Binding<Int>,
                in bounds: ClosedRange<Int>, accent: Color) {
        _low = low
        _high = high
        self.bounds = bounds
        self.accent = accent
    }

    public var body: some View {
        GeometryReader { geo in
            let span = max(1, bounds.upperBound - bounds.lowerBound)
            let usable = max(1, geo.size.width - thumb)
            let x = { (value: Int) in
                thumb / 2 + usable * CGFloat(value - bounds.lowerBound) / CGFloat(span)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.08))
                    .frame(height: trackHeight)
                Capsule().fill(accent.opacity(0.85))
                    .frame(width: max(0, x(high) - x(low)), height: trackHeight)
                    .offset(x: x(low))

                handle(at: x(low), label: low + 1)
                handle(at: x(high), label: high + 1)
            }
            .frame(height: thumb + 22, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let value = value(at: drag.location.x, usable: usable, span: span)
                        // Claim the nearer handle once, then keep it: releasing
                        // it when the drag crosses over would make the other
                        // handle jump to the finger.
                        let handle = dragging ?? (
                            abs(value - low) <= abs(value - high) ? .low : .high)
                        dragging = handle
                        switch handle {
                        case .low: low = min(value, high)
                        case .high: high = max(value, low)
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .frame(height: thumb + 22)
    }

    private func value(at x: CGFloat, usable: CGFloat, span: Int) -> Int {
        let fraction = min(1, max(0, (x - thumb / 2) / usable))
        return bounds.lowerBound + Int((fraction * CGFloat(span)).rounded())
    }

    private func handle(at x: CGFloat, label: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(label)")
                .font(.kawaii(12, weight: .bold)).monospacedDigit()
                .foregroundStyle(accent)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Palette.card, in: Capsule())
                .shadow(color: Palette.ink.opacity(0.08), radius: 2, y: 1)
            Circle()
                .fill(Palette.card)
                .overlay(Circle().stroke(accent, lineWidth: 3))
                .shadow(color: accent.opacity(0.3), radius: 4, y: 2)
                .frame(width: thumb, height: thumb)
        }
        .offset(x: x - thumb / 2, y: -9)
    }
}

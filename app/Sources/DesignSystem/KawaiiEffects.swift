import SwiftUI

// Playful motion + decoration shared across the home and study screens: a
// springy button style, an animated progress ring, drifting pastel blobs for a
// lively background, and a pop-in appear modifier. All decoration-only and
// dependency-free.

/// A button style that springs inward on press for a bouncy, tactile feel, and
/// lifts a touch on pointer hover (iPad pointer / Mac Catalyst).
public struct BouncyButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        BouncyLabel(configuration: configuration)
    }

    /// A small wrapper so the style can hold hover state (ButtonStyle itself
    /// can't) — hover gently scales up + brightens; press springs inward.
    private struct BouncyLabel: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : (hovering ? 1.03 : 1))
                .brightness(configuration.isPressed ? -0.03 : (hovering ? 0.02 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    public static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }
}

/// A circular progress ring with a candy gradient sweep and a rounded cap. The
/// ring animates from zero on appear. Any content (a number, an emoji) sits in
/// the center via the trailing closure.
public struct ProgressRing<Center: View>: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let colors: [Color]
    let center: Center

    @State private var animated = false

    public init(
        progress: Double, size: CGFloat = 150, lineWidth: CGFloat = 16,
        colors: [Color] = [Palette.pink, Palette.lavender, Palette.sky, Palette.mint, Palette.pink],
        @ViewBuilder center: () -> Center
    ) {
        self.progress = max(0, min(1, progress))
        self.size = size
        self.lineWidth = lineWidth
        self.colors = colors
        self.center = center()
    }

    private var gradient: AngularGradient {
        AngularGradient(colors: colors, center: .center)
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.pinkSoft, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // Soft static glow behind the arc.
            Circle()
                .trim(from: 0, to: animated ? progress : 0)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: 9)
                .opacity(0.55)
            Circle()
                .trim(from: 0, to: animated ? progress : 0)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size, height: size)
        .onAppear {
            // One-shot fill-in only — no perpetual sweep/glow redraws.
            withAnimation(.spring(response: 1.0, dampingFraction: 0.72).delay(0.15)) {
                animated = true
            }
        }
    }
}

/// Soft pastel blobs, a decorative backdrop behind card content. Static: the
/// former drift animation redrew five large blurred circles every frame,
/// compounding the aurora's main-thread cost. Non-interactive, safe-area
/// ignoring.
public struct FloatingBlobs: View {
    public init() {}

    private struct Blob: Identifiable {
        let id = UUID()
        let color: Color
        let diameter: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    private let blobs: [Blob] = [
        Blob(color: Palette.pinkSoft, diameter: 240, x: 0.12, y: 0.10),
        Blob(color: Palette.mintSoft, diameter: 190, x: 0.88, y: 0.22),
        Blob(color: Palette.lavenderSoft, diameter: 220, x: 0.80, y: 0.82),
        Blob(color: Palette.butterSoft, diameter: 160, x: 0.18, y: 0.88),
        Blob(color: Palette.skySoft, diameter: 130, x: 0.5, y: 0.5),
    ]

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(blobs) { blob in
                    Circle()
                        .fill(blob.color)
                        .frame(width: blob.diameter, height: blob.diameter)
                        .blur(radius: 42)
                        .opacity(0.55)
                        .position(x: geo.size.width * blob.x, y: geo.size.height * blob.y)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Springy pop-in on appear (scale + fade), optionally staggered by `delay`.
private struct PopIn: ViewModifier {
    let delay: Double
    @State private var shown: Bool

    init(delay: Double, animated: Bool) {
        self.delay = delay
        // Start visible when the entrance is off, so the row paints on its very
        // first frame instead of fading up from nothing.
        _shown = State(initialValue: !animated)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.82)
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Springy scale+fade entrance. Stagger a list by passing increasing delays.
    ///
    /// Pass `animated: false` for anything that can appear as a result of
    /// scrolling. In a `LazyVStack` a row is built the moment it scrolls into
    /// view, so an entrance animation there starts every row at opacity 0 —
    /// scroll quickly and you outrun it, leaving a screen of blank rows.
    /// The entrance is for the first paint, not for scrolling.
    public func popIn(delay: Double = 0, animated: Bool = true) -> some View {
        modifier(PopIn(delay: delay, animated: animated))
    }

    /// Entrance for a row at `index`: animated only for the rows already on
    /// screen at first paint, instant for everything scrolling in behind them.
    public func popInRow(_ index: Int, step: Double = 0.03,
                         onscreen: Int = 12) -> some View {
        popIn(delay: Double(min(index, onscreen)) * step, animated: index < onscreen)
    }
}

/// A slow, gentle scale pulse — subtle "breathing" for hero elements.
private struct Breathe: ViewModifier {
    let amount: CGFloat
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? amount : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

extension View {
    /// A slow continuous scale pulse (default ~4%). Decoration only.
    public func breathe(_ amount: CGFloat = 1.04) -> some View { modifier(Breathe(amount: amount)) }
}

/// A soft pastel mesh-gradient backdrop (candy aurora). Rendered statically: a
/// per-frame `TimelineView(.animation)` redraw of a full-screen mesh kept the
/// main thread busy on every screen (worst on Mac), which made buttons feel
/// laggy and dropped taps. A still gradient looks nearly identical and costs
/// nothing to keep on screen.
public struct AuroraBackground: View {
    public init() {}

    private let colors: [Color] = [
        Palette.pinkSoft, Palette.background, Palette.skySoft,
        Palette.lavenderSoft, Palette.background, Palette.mintSoft,
        Palette.butterSoft, Palette.pinkSoft, Palette.skySoft,
    ]

    public var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                .init(0, 0), .init(0.52, 0), .init(1, 0),
                .init(0, 0.46), .init(0.56, 0.52), .init(1, 0.44),
                .init(0, 1), .init(0.48, 1), .init(1, 1),
            ],
            colors: colors)
        .ignoresSafeArea()
        .allowsHitTesting(false)  // purely decorative — never intercept taps
    }
}

/// A one-shot confetti burst that rains pastel pieces down and fades out.
/// Deterministic (seeded by index) so it needs no random source.
public struct ConfettiView: View {
    let count: Int
    @State private var fall = false

    public init(count: Int = 40) { self.count = count }

    private let colors: [Color] = [
        Palette.pink, Palette.mint, Palette.lavender, Palette.butter, Palette.sky,
    ]

    /// Deterministic pseudo-random in 0...1 from a seed.
    private func rnd(_ seed: Double) -> Double {
        let v = sin(seed * 12.9898) * 43_758.5453
        return v - v.rounded(.down)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let d = Double(i)
                    let startX = geo.size.width * rnd(d)
                    let drift = CGFloat(rnd(d + 3) - 0.5) * 80
                    let sizePx = CGFloat(6 + rnd(d + 5) * 8)
                    let delay = rnd(d + 7) * 0.5
                    let duration = 1.5 + rnd(d + 9) * 1.0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(colors[i % colors.count])
                        .frame(width: sizePx, height: sizePx * 1.4)
                        .position(x: startX + (fall ? drift : 0),
                                  y: fall ? geo.size.height + 40 : -40)
                        .rotationEffect(.degrees(fall ? 360 * (rnd(d + 11) * 2 - 1) : 0))
                        .opacity(fall ? 0 : 1)
                        .animation(.easeIn(duration: duration).delay(delay), value: fall)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { fall = true }
    }
}

/// A looping celebratory bounce + wiggle for a badge/emoji on completion screens.
private struct Celebrate: ViewModifier {
    @State private var animate = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.12 : 0.92)
            .rotationEffect(.degrees(animate ? 7 : -7))
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.45)
                    .repeatForever(autoreverses: true)) { animate = true }
            }
    }
}

extension View {
    /// A never-ending celebratory bounce+wiggle (for 🎉 on done screens).
    public func celebrate() -> some View { modifier(Celebrate()) }
}

/// A pulsing ring of sparkles radiating outward — a flourish behind completion
/// badges.
public struct Sparkles: View {
    var count = 10
    var radius: CGFloat = 66
    @State private var on = false

    public init(count: Int = 10, radius: CGFloat = 66) {
        self.count = count
        self.radius = radius
    }

    public var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: i.isMultiple(of: 2) ? 16 : 11))
                    .foregroundStyle(i.isMultiple(of: 2) ? Palette.butter : Palette.pink)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(i) / Double(count) * 360))
                    .scaleEffect(on ? 1 : 0.2)
                    .opacity(on ? 0.9 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

import SwiftUI

// Playful motion + decoration shared across the home and study screens: a
// springy button style, an animated progress ring, drifting pastel blobs for a
// lively background, and a pop-in appear modifier. All decoration-only and
// dependency-free.

/// A button style that springs inward on press for a bouncy, tactile feel.
public struct BouncyButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
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
    @State private var glow = false

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
            // Soft breathing glow behind the arc.
            Circle()
                .trim(from: 0, to: animated ? progress : 0)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: 9)
                .opacity(glow ? 0.85 : 0.35)
            Circle()
                .trim(from: 0, to: animated ? progress : 0)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.72).delay(0.15)) {
                animated = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

/// Softly drifting pastel blobs, used as a lively decorative backdrop behind
/// card content. Non-interactive and safe-area ignoring.
public struct FloatingBlobs: View {
    @State private var drift = false
    public init() {}

    private struct Blob: Identifiable {
        let id = UUID()
        let color: Color
        let diameter: CGFloat
        let x: CGFloat
        let y: CGFloat
        let up: Bool
    }

    private let blobs: [Blob] = [
        Blob(color: Palette.pinkSoft, diameter: 240, x: 0.12, y: 0.10, up: true),
        Blob(color: Palette.mintSoft, diameter: 190, x: 0.88, y: 0.22, up: false),
        Blob(color: Palette.lavenderSoft, diameter: 220, x: 0.80, y: 0.82, up: true),
        Blob(color: Palette.butterSoft, diameter: 160, x: 0.18, y: 0.88, up: false),
        Blob(color: Palette.skySoft, diameter: 130, x: 0.5, y: 0.5, up: true),
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
                        .position(
                            x: geo.size.width * blob.x,
                            y: geo.size.height * blob.y + (drift == blob.up ? -20 : 20))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}

/// Springy pop-in on appear (scale + fade), optionally staggered by `delay`.
private struct PopIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.82)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Springy scale+fade entrance. Stagger a list by passing increasing delays.
    public func popIn(delay: Double = 0) -> some View { modifier(PopIn(delay: delay)) }
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

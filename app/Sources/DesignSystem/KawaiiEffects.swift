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

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.pinkSoft, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: animated ? progress : 0)
                .stroke(
                    AngularGradient(colors: colors, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.pink.opacity(0.3), radius: 6)
            center
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.72).delay(0.15)) {
                animated = true
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

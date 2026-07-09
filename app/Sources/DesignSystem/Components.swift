import SwiftUI

// Reusable kawaii-pastel building blocks shared by every screen. Each piece has
// one job, takes its colors explicitly, and carries no feature dependency.
// (The `Font.kawaii` cute-font helpers live in Fonts.swift.)

extension View {
    /// Wraps content in a soft white rounded card with a gentle shadow.
    public func roundedCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Palette.ink.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

/// A small candy-colored pill — used for JLPT / grade badges and filter chips.
public struct CandyChip: View {
    let text: String
    let soft: Color
    let accent: Color
    var selected: Bool

    public init(_ text: String, soft: Color, accent: Color, selected: Bool = false) {
        self.text = text
        self.soft = soft
        self.accent = accent
        self.selected = selected
    }

    public var body: some View {
        Text(text)
            .font(.kawaii(14, weight: .bold))
            .foregroundStyle(selected ? Color.white : accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if selected {
                    LinearGradient(colors: [accent, accent.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    soft
                }
            }
            .clipShape(Capsule())
            .shadow(color: selected ? accent.opacity(0.35) : .clear, radius: 5, y: 2)
    }
}

/// A rounded pastel tile holding a single large kanji glyph.
public struct PastelTile: View {
    @Environment(\.japaneseFont) private var jpFont
    let glyph: String
    let soft: Color
    let accent: Color
    var size: CGFloat
    var fontSize: CGFloat

    public init(
        _ glyph: String, soft: Color, accent: Color,
        size: CGFloat = 60, fontSize: CGFloat = 34
    ) {
        self.glyph = glyph
        self.soft = soft
        self.accent = accent
        self.size = size
        self.fontSize = fontSize
    }

    public var body: some View {
        let corner = min(22, size * 0.3)
        return Text(glyph)
            .font(.kawaiiJP(fontSize, weight: .bold, font: jpFont))
            .japaneseGlyphs()
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    // Candy gradient fill.
                    LinearGradient(colors: [soft.opacity(0.65), soft],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    // Soft top gloss for a glassy, kawaii sheen.
                    LinearGradient(colors: [.white.opacity(0.5), .clear],
                                   startPoint: .top, endPoint: .center)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(accent.opacity(0.4), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: accent.opacity(0.28), radius: size * 0.09, y: size * 0.045)
    }
}

/// A section header with a small colored dot accent.
public struct SectionHeader: View {
    let title: String
    let accent: Color

    public init(_ title: String, accent: Color) {
        self.title = title
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 9, height: 9)
            Text(title).font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
        }
    }
}

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
            .background(selected ? accent : soft)
            .clipShape(Capsule())
    }
}

/// A rounded pastel tile holding a single large kanji glyph.
public struct PastelTile: View {
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
        Text(glyph)
            .font(.kawaii(fontSize, weight: .bold))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(soft)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

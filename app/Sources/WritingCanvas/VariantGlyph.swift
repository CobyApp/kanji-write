import DesignSystem
import SharedModels
import SwiftUI

/// A kanji drawn from an outline rather than typed as text.
///
/// 旧字 forms have no codepoint of their own — that is the whole reason the 漢検
/// list prints them as pictures — so there is no character to put in a `Text`.
/// What we have is one filled path on a square box, which draws the same shape
/// at any size and in the reader's own colour scheme, unlike the bitmap.
public struct VariantGlyph: View {
    private let variant: KanjiVariant
    private let size: CGFloat

    public init(_ variant: KanjiVariant, size: CGFloat = 64) {
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        OutlineShape(d: variant.pathD, box: CGFloat(variant.viewBox))
            .fill(Palette.ink)
            .frame(width: size, height: size)
            .accessibilityLabel(Text(variant.variantKind))
    }
}

/// The outline scaled to whatever rect it is given.
///
/// Filled with the non-zero rule, which is what the SVG declares — GlyphWiki
/// sets no `fill-rule`. The two rules happen to agree on every one of these
/// glyphs (checked across 300 of them), because each stroke is authored as its
/// own closed, non-overlapping region rather than as shapes laid over one
/// another. Following the file is still the right default.
private struct OutlineShape: Shape {
    let d: String
    let box: CGFloat

    func path(in rect: CGRect) -> Path {
        guard box > 0 else { return Path() }
        let scale = min(rect.width, rect.height) / box
        return SVGPath.path(from: SVGPath.parse(d))
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

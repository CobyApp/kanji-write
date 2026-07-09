import Foundation
import SharedModels
import SwiftUI

/// Runtime furigana (よみかた) generation. The bundled sentences store only the
/// Japanese text, so readings are produced on the fly with the system Japanese
/// tokenizer: each word's Latin transcription is converted to hiragana. Accuracy
/// follows the OS dictionary — good enough as a reading aid over example text.
public enum Furigana {
    /// A run of the sentence: `base` text plus its kana `reading` (nil for kana,
    /// punctuation, or when no reading is available).
    public struct Token: Equatable {
        public let base: String
        public let reading: String?
    }

    public static func tokens(_ text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let cf = text as CFString
        let full = CFRangeMake(0, CFStringGetLength(cf))
        let locale = Locale(identifier: "ja_JP") as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            nil, cf, full, kCFStringTokenizerUnitWordBoundary, locale)

        var result: [Token] = []
        var lastEnd = 0
        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while type.rawValue != 0 {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // Preserve any gap (spaces / punctuation) before this token.
            if r.location > lastEnd {
                result.append(Token(base: ns.substring(with: NSRange(
                    location: lastEnd, length: r.location - lastEnd)), reading: nil))
            }
            let base = ns.substring(with: NSRange(location: r.location, length: r.length))
            var reading: String?
            if base.containsKanji,
               let attr = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription),
               let latin = attr as? String {
                let kana = hiragana(from: latin)
                if !kana.isEmpty, kana != base { reading = kana }
            }
            result.append(Token(base: base, reading: reading))
            lastEnd = r.location + r.length
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        let total = CFStringGetLength(cf)
        if lastEnd < total {
            result.append(Token(base: ns.substring(with: NSRange(
                location: lastEnd, length: total - lastEnd)), reading: nil))
        }
        return result
    }

    private static func hiragana(from latin: String) -> String {
        let m = NSMutableString(string: latin) as CFMutableString
        CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false)
        return (m as String)
    }
}

extension String {
    /// True if the string contains at least one CJK ideograph (kanji).
    fileprivate var containsKanji: Bool {
        unicodeScalars.contains { s in
            (0x4E00...0x9FFF).contains(s.value) ||  // CJK Unified
            (0x3400...0x4DBF).contains(s.value) ||  // Extension A
            (0xF900...0xFAFF).contains(s.value)     // Compatibility
        }
    }
}

/// Example text with furigana rendered as ruby (small kana above each kanji
/// word). Wraps across lines. Kana/punctuation runs show no ruby.
public struct RubyText: View {
    let text: String
    let size: CGFloat
    let color: Color

    public init(_ text: String, size: CGFloat = 18, color: Color = Palette.ink) {
        self.text = text
        self.size = size
        self.color = color
    }

    public var body: some View {
        RubyFlow(spacing: 0, lineSpacing: 6) {
            ForEach(Array(Furigana.tokens(text).enumerated()), id: \.offset) { _, token in
                VStack(spacing: 1) {
                    // A zero-opacity placeholder keeps every base glyph on the same
                    // baseline whether or not it has a reading above it.
                    Text(token.reading ?? " ")
                        .font(.kawaii(size * 0.62, weight: .bold)).foregroundStyle(Palette.pink)
                        .opacity(token.reading == nil ? 0 : 1)
                    Text(token.base)
                        .font(.kawaiiJP(size, weight: .bold)).foregroundStyle(color)
                        .japaneseGlyphs()
                }
                .fixedSize()
            }
        }
    }
}

/// A word shown with its known reading as ruby above the whole surface (group
/// ruby). Falls back to just the surface when the reading is empty or identical
/// (kana-only words).
public struct RubyWord: View {
    let surface: String
    let reading: String
    let size: CGFloat

    public init(_ surface: String, reading: String, size: CGFloat = 20) {
        self.surface = surface
        self.reading = reading
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !reading.isEmpty, reading != surface {
                Text(reading)
                    .font(.kawaii(size * 0.62, weight: .bold)).foregroundStyle(Palette.pink)
            }
            Text(surface)
                .font(.kawaiiJP(size, weight: .bold)).foregroundStyle(Palette.ink)
                .japaneseGlyphs()
        }
    }
}

/// A minimal wrapping layout — lays children left-to-right, wrapping to a new
/// line when the row is full. Used to flow ruby word-cells.
struct RubyFlow: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let sz = view.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                widest = max(widest, x - spacing)
                x = 0; y += lineH + lineSpacing; lineH = 0
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(maxW, max(0, widest)), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for view in subviews {
            let sz = view.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + maxW, x > bounds.minX {
                x = bounds.minX; y += lineH + lineSpacing; lineH = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

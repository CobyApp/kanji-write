import SharedModels
import SwiftUI

/// The canonical kanji row: pastel glyph tile + meaning · JLPT level · stroke
/// count, then 음(on)/훈(kun) reading chips, with a chevron. Shared so the 한자
/// section in a word's detail looks identical to a row in the 한자사전.
public struct KanjiListRow: View {
    private let kanji: Kanji
    private let meaning: String?
    private let tint: (soft: Color, accent: Color)
    private let language: AppLanguage
    private let onSelect: () -> Void

    public init(kanji: Kanji, meaning: String?, tint: (soft: Color, accent: Color),
                language: AppLanguage, onSelect: @escaping () -> Void) {
        self.kanji = kanji
        self.meaning = meaning
        self.tint = tint
        self.language = language
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                           size: 56, fontSize: 30)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        if let meaning, !meaning.isEmpty {
                            Text(meaning)
                                .font(.kawaii(15, weight: .bold, language: language))
                                .foregroundStyle(Palette.ink)
                        }
                        if let level = kanji.jlptLevel {
                            Text(level).font(.kawaii(11, weight: .bold))
                                .foregroundStyle(Palette.inkSoft)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Palette.background).clipShape(Capsule())
                        }
                        Text("\(kanji.strokeCount)\(L.strokesUnit[language])")
                            .font(.kawaii(11)).foregroundStyle(Palette.inkSoft)
                    }
                    if !kanji.onReadings.isEmpty {
                        readingLine(L.onReading[language], kanji.onReadings, Palette.sky)
                    }
                    if !kanji.kunReadings.isEmpty {
                        readingLine(L.kunReading[language], kanji.kunReadings, Palette.mint)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.inkSoft)
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }

    /// A 음/훈 reading line with a colored label chip.
    private func readingLine(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.kawaii(10, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(accent).clipShape(Capsule())
            Text(readings.prefix(6).joined(separator: "、"))
                .font(.kawaiiJP(13, weight: .semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
        }
    }
}

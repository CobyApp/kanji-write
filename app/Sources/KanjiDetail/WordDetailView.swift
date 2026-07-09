import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

public struct WordDetailView: View {
    @Bindable public var store: StoreOf<WordDetailFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: StoreOf<WordDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header.popIn(delay: 0.02)
                    if !store.kanji.isEmpty { kanjiSection.popIn(delay: 0.10) }
                    // Writing practice is an Apple-Pencil activity → iPad only.
                    if Platform.isPad { tracingSection.popIn(delay: 0.16) }
                    if !store.sentences.isEmpty { sentencesSection.popIn(delay: 0.22) }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
        }
        .navigationTitle(store.word.surface)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(store.addedToWordbook ? L.addedToWordbook[appLanguage] : L.addToWordbook[appLanguage]) {
                store.send(.addToWordbook)
            }
            .disabled(store.addedToWordbook)
        }
        .task { store.send(.onAppear) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(store.word.surface)
                    .font(.kawaiiJP(34, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink)
                SpeakButton(store.word.surface)
            }
            Text(store.word.reading)
                .font(.kawaii(17)).foregroundStyle(Palette.inkSoft)
            if let meaning = wordMeaning(store.word, appLanguage) {
                Text(meaning)
                    .font(.kawaii(18, weight: .semibold, language: appLanguage))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundedCard()
    }

    private var kanjiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.kanji[appLanguage], accent: Palette.mint)
            ForEach(Array(store.kanji.enumerated()), id: \.element.id) { index, kanji in
                kanjiRow(kanji, tint: Palette.tint(index))
            }
        }
        .roundedCard()
    }

    /// A rich per-kanji row: glyph + meaning + 음/훈 readings, tap → kanji detail.
    private func kanjiRow(_ kanji: Kanji, tint: (soft: Color, accent: Color)) -> some View {
        Button { store.send(.kanjiTapped(kanji)) } label: {
            HStack(spacing: 14) {
                PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent, size: 58, fontSize: 33)
                VStack(alignment: .leading, spacing: 5) {
                    if let meaning = localizedGloss(store.glossesByID[kanji.id] ?? [:], appLanguage),
                       !meaning.isEmpty {
                        Text(meaning)
                            .font(.kawaii(16, weight: .bold, language: appLanguage))
                            .foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    }
                    if !kanji.onReadings.isEmpty {
                        readingLine(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
                    }
                    if !kanji.kunReadings.isEmpty {
                        readingLine(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.inkSoft)
            }
            .padding(12)
            .background(tint.soft.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.bouncy)
    }

    /// A 음/훈 reading line with a colored label chip.
    private func readingLine(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.kawaii(11, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(accent).clipShape(Capsule())
            Text(readings.prefix(5).joined(separator: "、"))
                .font(.kawaii(14, weight: .semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
        }
    }

    /// One tracing cell per character of the word (kanji show their stroke guide;
    /// kana show the faint glyph template).
    private var traceChars: [WordTracingGrid.Char] {
        Array(store.word.surface.enumerated()).map { index, character in
            let glyph = String(character)
            let paths = store.kanji.first { $0.literal == glyph }
                .flatMap { store.strokesByID[$0.id] } ?? []
            return WordTracingGrid.Char(id: index, glyph: glyph, paths: paths)
        }
    }

    private var tracingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.practiceWriting[appLanguage], accent: Palette.pink)
            WordTracingGrid(characters: traceChars, showGuide: true)
        }
        .roundedCard()
    }

    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.examples[appLanguage], accent: Palette.butter)
            ForEach(store.sentences) { sentence in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sentence.textJa)
                            .font(.kawaiiJP(16)).japaneseGlyphs().foregroundStyle(Palette.ink)
                        if let translation = localizedTranslation(sentence.translations, appLanguage) {
                            Text(translation).font(.kawaii(14, language: appLanguage))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SpeakButton(sentence.textJa)
                }
            }
        }
        .roundedCard()
    }
}

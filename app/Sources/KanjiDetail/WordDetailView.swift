import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

public struct WordDetailView: View {
    @Bindable public var store: StoreOf<WordDetailFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

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
                    // Writing practice is available on every device (finger tracing
                    // works on iPhone too), not just iPad.
                    tracingSection.popIn(delay: 0.16)
                    if !store.sentences.isEmpty { sentencesSection.popIn(delay: 0.22) }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            NavHeader(title: store.word.surface, onBack: { dismiss() }) {
                CircleButton(store.addedToWordbook ? "bookmark.fill" : "bookmark", size: 34) {
                    store.send(.addToWordbook)
                }
                .accessibilityLabel(store.addedToWordbook ? L.addedToWordbook[appLanguage] : L.addToWordbook[appLanguage])
                .disabled(store.addedToWordbook)
            }
            .background(Palette.background)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.kanji[appLanguage], accent: Palette.mint)
            // Identical row to a 한자사전 entry (white card) so the two match.
            ForEach(Array(store.kanji.enumerated()), id: \.element.id) { index, kanji in
                KanjiListRow(kanji: kanji,
                             meaning: localizedGloss(store.glossesByID[kanji.id] ?? [:], appLanguage),
                             tint: Palette.tint(index),
                             language: appLanguage) { store.send(.kanjiTapped(kanji)) }
            }
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

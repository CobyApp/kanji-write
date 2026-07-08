import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

public struct KanjiDetailView: View {
    @Bindable public var store: StoreOf<KanjiDetailFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<KanjiDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header.popIn(delay: 0.02)
                    readings.popIn(delay: 0.09)
                    if !store.strokePaths.isEmpty { strokeOrderSection.popIn(delay: 0.16) }
                    if !store.words.isEmpty { wordsSection.popIn(delay: 0.22) }
                    if !store.sentences.isEmpty { sentencesSection.popIn(delay: 0.28) }
                    if !store.relations.isEmpty { relationsSection.popIn(delay: 0.34) }
                }
                .padding(16)
            }
        }
        .navigationTitle(store.kanji.literal)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { store.send(.toggleBookmark) } label: {
                Image(systemName: store.isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(store.isBookmarked ? Palette.butter : Palette.inkSoft)
            }
            .accessibilityLabel(L.bookmark[appLanguage])
            Button(store.addedToReview ? L.addedToReview[appLanguage] : L.addToReview[appLanguage]) {
                store.send(.addToReview)
            }
            .disabled(store.addedToReview)
            Button(L.practiceWriting[appLanguage]) { store.send(.writeTapped) }
        }
        .task { store.send(.onAppear) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            PastelTile(store.kanji.literal, soft: Palette.pinkSoft, accent: Palette.pink,
                       size: 96, fontSize: 60)
                .breathe(1.03)
            VStack(alignment: .leading, spacing: 10) {
                Text(localizedGloss(store.glosses, appLanguage) ?? "")
                    .font(.kawaii(24, weight: .bold, language: appLanguage))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    if let grade = store.kanji.grade {
                        CandyChip("学\(grade)", soft: Palette.butterSoft, accent: Palette.butter)
                    }
                    if let jlpt = store.kanji.jlptLevel {
                        CandyChip(jlpt, soft: Palette.skySoft, accent: Palette.sky)
                    }
                    if let radical = store.kanji.radicalGlyph {
                        CandyChip("\(L.radical[appLanguage]) \(radical)",
                                  soft: Palette.mintSoft, accent: Palette.mint)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .roundedCard()
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L.readings[appLanguage], accent: Palette.pink)
            if !store.kanji.onReadings.isEmpty {
                Text(L.onReading[appLanguage] + " " + store.kanji.onReadings.joined(separator: "、"))
                    .font(.kawaii(16)).foregroundStyle(Palette.ink)
            }
            if !store.kanji.kunReadings.isEmpty {
                Text(L.kunReading[appLanguage] + " " + store.kanji.kunReadings.joined(separator: "、"))
                    .font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            }
        }
        .roundedCard()
    }

    private var strokeOrderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.strokeOrder[appLanguage], accent: Palette.mint)
            StrokeOrderPlayer(paths: store.strokePaths)
        }
        .roundedCard()
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.words[appLanguage], accent: Palette.lavender)
            ForEach(store.words) { word in
                HStack(spacing: 8) {
                    Button { store.send(.wordTapped(word)) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                RubyWord(word.surface, reading: word.reading, size: 17)
                                if let meaning = wordMeaning(word, appLanguage) {
                                    Text(meaning).font(.kawaii(13, language: appLanguage))
                                        .foregroundStyle(Palette.inkSoft)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    SpeakButton(word.surface)
                }
            }
        }
        .roundedCard()
    }

    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.examples[appLanguage], accent: Palette.butter)
            ForEach(store.sentences) { sentence in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        RubyText(sentence.textJa, size: 17)
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

    private var relationsSection: some View {
        let antonyms = store.relations.filter { $0.type == "antonym" }.map(\.surface)
        let related = store.relations.filter { $0.type == "related" }.map(\.surface)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L.related[appLanguage], accent: Palette.sky)
            if !antonyms.isEmpty {
                Text(L.antonym[appLanguage]).font(.kawaii(14, weight: .bold)).foregroundStyle(Palette.inkSoft)
                Text(antonyms.joined(separator: "、"))
                    .font(.kawaii(16)).foregroundStyle(Palette.ink)
            }
            if !related.isEmpty {
                Text(L.relatedWords[appLanguage]).font(.kawaii(14, weight: .bold)).foregroundStyle(Palette.inkSoft)
                Text(related.joined(separator: "、"))
                    .font(.kawaii(16)).foregroundStyle(Palette.ink)
            }
        }
        .roundedCard()
    }
}

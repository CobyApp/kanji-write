import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

public struct KanjiDetailView: View {
    @Bindable public var store: StoreOf<KanjiDetailFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

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
                .readableWidth(sizeClass)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            // A single 단어장(보관함) toggle — the kanji joins the same collection
            // the Home 단어장 manages. (Review/write practice moved out of here.)
            NavHeader(title: store.kanji.literal, onBack: { dismiss() }) {
                CircleButton(store.isBookmarked ? "bookmark.fill" : "bookmark", size: 34) {
                    store.send(.toggleBookmark)
                }
                .accessibilityLabel(store.isBookmarked ? L.addedToWordbook[appLanguage] : L.addToWordbook[appLanguage])
            }
            .background(Palette.background)
        }
        .safeAreaInset(edge: .bottom) {
            if store.siblings.count > 1 { siblingNav }
        }
        .task { store.send(.onAppear) }
    }

    /// Prev/next through the list this kanji was opened from — step to the
    /// neighbouring kanji without returning to the list.
    private var siblingNav: some View {
        HStack(spacing: 12) {
            siblingButton(L.prev[appLanguage], icon: "chevron.left",
                          enabled: store.hasPrev) { store.send(.showSibling(delta: -1)) }
            siblingButton(L.next[appLanguage], icon: "chevron.right", trailingIcon: true,
                          enabled: store.hasNext) { store.send(.showSibling(delta: 1)) }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .readableWidth(sizeClass)
        .background(Palette.background)
    }

    private func siblingButton(_ title: String, icon: String, trailingIcon: Bool = false,
                               enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !trailingIcon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(.kawaii(16, weight: .bold, language: appLanguage))
                if trailingIcon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
            }
            .foregroundStyle(enabled ? .white : Palette.inkSoft)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(enabled ? Palette.accent : Palette.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(enabled ? .clear : Palette.ink.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                    // The level tag follows the active exam — 漢検 급수 or JLPT レベル.
                    if let level = store.kanji.level(for: examType) {
                        CandyChip(level, soft: Palette.skySoft, accent: Palette.sky)
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
                                RubyWord(word.surface, reading: word.reading, size: 18)
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
                        RubyText(sentence.textJa, size: 18)
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
                relationChips(antonyms, tint: Palette.pink)
            }
            if !related.isEmpty {
                Text(L.relatedWords[appLanguage]).font(.kawaii(14, weight: .bold)).foregroundStyle(Palette.inkSoft)
                relationChips(related, tint: Palette.sky)
            }
        }
        .roundedCard()
    }

    /// Tappable word chips — each resolves to its word detail (kanji↔word nav).
    private func relationChips(_ surfaces: [String], tint: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(surfaces, id: \.self) { surface in
                    Button { store.send(.relationTapped(surface)) } label: {
                        Text(surface)
                            .font(.kawaiiJP(16, weight: .semibold)).japaneseGlyphs()
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(tint.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.bouncy)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

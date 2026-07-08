import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI
import WritingCanvas

/// The word meaning for the selected language, falling back to English.
/// (Reimplemented inline so Worksheet does not depend on KanjiDetail.)
private func wordMeaning(_ word: WordEntry, _ language: AppLanguage) -> String? {
    switch language {
    case .ko: return word.meaningKo ?? word.meaningEn
    case .ja: return word.meaningJa ?? word.meaningEn
    case .zh: return word.meaningZh ?? word.meaningEn
    case .en: return word.meaningEn
    }
}

/// A sentence translation for the selected language. Japanese mode shows no
/// translation (the example is already Japanese); others fall back to English.
private func localizedTranslation(_ translations: [String: String], _ language: AppLanguage) -> String? {
    if language == .ja { return nil }
    for key in [language.glossKey, "ko", "zh", "en"] {
        if let value = translations[key], !value.isEmpty { return value }
    }
    return nil
}

/// The kanji's own meaning for the selected language, falling back deterministically.
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

/// A guided study-sheet (학습) for today's NEW kanji. For each kanji: write it
/// once over the stroke-order guide, read one word that uses it, and one example
/// sentence. Finishing schedules them all for review (initial FSRS record).
public struct WorksheetView: View {
    @Bindable public var store: StoreOf<WorksheetFeature>
    @AppStorage("newPerDay") private var newPerDay = 7
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Which card of the current kanji is showing (0…3). Card 4 is a sentinel
    /// that means "swiped past the last card" → advance to the next kanji.
    @State private var card = 0

    public init(store: StoreOf<WorksheetFeature>) {
        self.store = store
    }

    private func advance() {
        // Advancing changes store.index, which resets `card` to 0 without
        // animation (see the .onChange in `content`).
        store.send(store.isLast ? .doneTapped : .nextTapped)
    }

    public var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle(L.study[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear(newPerDay: max(1, newPerDay), level: targetLevel)) }
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasLoaded {
            loadingCard
        } else if store.isFinished {
            finishedCard
        } else if store.queue.isEmpty {
            emptyCard
        } else if let kanji = store.current {
            VStack(spacing: 12) {
                deckHeader
                TabView(selection: $card) {
                    cardShell { meaningCard(kanji) }.tag(0)
                    cardShell { strokeCard(kanji) }.tag(1)
                    cardShell { wordCard }.tag(2)
                    cardShell { exampleCard }.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Reset to the first card on a new kanji WITHOUT animating (avoids a
                // long multi-page slide-back).
                .onChange(of: store.index) { _, _ in
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { card = 0 }
                }
                advanceButton
            }
            .padding(16)
        }
    }

    // MARK: Deck header (kanji counter + per-kanji card progress)

    private var deckHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(min(store.index + 1, store.queue.count)) / \(store.queue.count)")
                    .font(.kawaii(14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("\(targetLevel) · \(newPerDay)/\(L.daysUnit[appLanguage])")
                    .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= min(card, 3) ? Palette.pink : Palette.pinkSoft)
                        .frame(height: 5)
                }
            }
        }
    }

    /// Each card: a title + its content in a scrollable rounded card that fills
    /// the page (so long content still scrolls within the card).
    private func cardShell<Content: View>(@ViewBuilder _ body: @escaping () -> Content) -> some View {
        GeometryReader { geo in
            ScrollView {
                body()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
    }

    /// Shared card chrome: an icon+title header in the card's accent, content
    /// below, on a big rounded elevated panel. Gives every card one identity.
    private func studyCard<C: View>(
        _ title: String, _ icon: String, _ accent: Color,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title).font(.kawaii(17, weight: .bold, language: appLanguage))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(accent.opacity(0.28), lineWidth: 1.5))
        .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    // MARK: Card 1 — meaning + readings (뜻·읽기)

    private func meaningCard(_ kanji: Kanji) -> some View {
        let glyphSize: CGFloat = sizeClass == .compact ? 150 : 172
        return studyCard(L.readings[appLanguage], "textformat.size.larger", Palette.pink) {
            VStack(spacing: 16) {
                PastelTile(kanji.literal, soft: Palette.pinkSoft, accent: Palette.pink,
                           size: glyphSize, fontSize: glyphSize * 0.62)
                    .breathe(1.03)
                if let meaning = localizedGloss(store.glosses, appLanguage), !meaning.isEmpty {
                    HStack(spacing: 8) {
                        Text(meaning)
                            .font(.kawaii(26, weight: .bold, language: appLanguage))
                            .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                        SpeakButton(kanji.literal)
                    }
                }
                VStack(spacing: 8) {
                    if !kanji.onReadings.isEmpty {
                        readingRow(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
                    }
                    if !kanji.kunReadings.isEmpty {
                        readingRow(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Card 2 — stroke order (획순)

    private func strokeCard(_ kanji: Kanji) -> some View {
        let glyphSize: CGFloat = sizeClass == .compact ? 230 : 210
        return studyCard(L.strokeOrder[appLanguage], "scribble.variable", Palette.mint) {
            Group {
                if store.strokePaths.isEmpty {
                    PastelTile(kanji.literal, soft: Palette.butterSoft, accent: Palette.butter,
                               size: glyphSize, fontSize: glyphSize * 0.62)
                } else {
                    // Auto-plays when this (the 2nd) card becomes the visible page.
                    StrokeOrderPlayer(paths: store.strokePaths, size: glyphSize, isActive: card == 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A centered 音/訓 reading row with a colored label chip.
    private func readingRow(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.kawaii(12, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent).clipShape(Capsule())
            Text(readings.joined(separator: "、"))
                .font(.kawaii(16, weight: .semibold)).foregroundStyle(Palette.ink)
        }
    }

    // MARK: 2) One word using the kanji

    @ViewBuilder
    private var wordCard: some View {
        studyCard(L.worksheetWord[appLanguage], "character.book.closed", Palette.lavender) {
            if store.words.isEmpty {
                Text("…").font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            } else {
                VStack(spacing: 12) {
                    ForEach(store.words) { word in
                        Button { store.send(.wordTapped(word)) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    RubyWord(word.surface, reading: word.reading, size: 22)
                                    if let meaning = wordMeaning(word, appLanguage), !meaning.isEmpty {
                                        Text(meaning)
                                            .font(.kawaii(14, language: appLanguage))
                                            .foregroundStyle(Palette.inkSoft)
                                    }
                                }
                                Spacer(minLength: 0)
                                SpeakButton(word.surface)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkSoft)
                            }
                            .padding(14)
                            .background(Palette.lavenderSoft.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bouncy)
                    }
                }
            }
        }
    }

    // MARK: Card 4 — example sentences (예문)

    @ViewBuilder
    private var exampleCard: some View {
        studyCard(L.worksheetExample[appLanguage], "text.quote", Palette.sky) {
            if store.sentences.isEmpty {
                Text("…").font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            } else {
                VStack(spacing: 12) {
                    ForEach(store.sentences) { sentence in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                RubyText(sentence.textJa, size: 20)
                                if let translation = localizedTranslation(sentence.translations, appLanguage),
                                   !translation.isEmpty {
                                    Text(translation)
                                        .font(.kawaii(14, language: appLanguage))
                                        .foregroundStyle(Palette.inkSoft)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            SpeakButton(sentence.textJa)
                        }
                        .padding(14)
                        .background(Palette.skySoft.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: Advance (Next / Done)

    private var advanceButton: some View {
        // On the last card, finishing the deck advances to the next kanji (or
        // completes); otherwise it flips to the next card. Swiping does the same.
        let lastCard = card >= 3
        let finishing = lastCard && store.isLast
        let label = finishing ? L.done[appLanguage] : L.next[appLanguage]
        let colors = finishing ? [Palette.mint, Palette.sky] : [Palette.butter, Palette.pink]
        return Button {
            if lastCard { advance() } else { withAnimation { card += 1 } }
        } label: {
            Text(label)
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
                .shadow(color: colors[0].opacity(0.4), radius: 10, y: 5)
        }
        .buttonStyle(.bouncy)
    }

    // MARK: Finished / empty

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Palette.mint)
            Text(L.doneToday[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.seeTomorrow[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
        .padding(16)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Text("🌸").font(.system(size: 52))
            Text(L.noLessons[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.seeTomorrow[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
        .padding(16)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Palette.pink)
            Text(L.toLearn[appLanguage])
                .font(.kawaii(15)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .roundedCard()
        .padding(16)
    }
}

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled to fit its square,
/// shown faintly behind the write canvas.
private struct GuideStrokes: View {
    private static let viewBoxSize: CGFloat = 109.0
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewBoxSize
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Palette.mint.opacity(0.35), lineWidth: 3)
            }
        }
    }
}

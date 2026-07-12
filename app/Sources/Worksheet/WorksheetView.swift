import ComposableArchitecture
import DesignSystem
import PencilKit
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
    /// Which card of the current kanji is showing (0…`lastCard`).
    @State private var card = 0
    /// The learner's tracing on the write card (iPad only). Cleared per kanji.
    @State private var writeDrawing = PKDrawing()
    /// Holds keyboard focus on the deck so ←/→ arrow keys drive prev/next.
    @FocusState private var deckFocused: Bool

    /// The write card (trace over the stroke guide) is an Apple-Pencil activity,
    /// so it's only part of the deck on iPad.
    private var showWrite: Bool { Platform.isPad }

    /// The kinds of study card, in deck order.
    private enum Step: Equatable { case meaning, stroke, write, onWords, kunWords, otherWords, verbs, example, quiz }

    /// Example words split by the reading they use, so each becomes its own card.
    private func wordGroups(_ kanji: Kanji) -> (on: [WordEntry], kun: [WordEntry], other: [WordEntry]) {
        let g = Dictionary(grouping: store.words) { classifyReading(word: $0, kanji: kanji) }
        return (g[.on] ?? [], g[.kun] ?? [], g[nil] ?? [])
    }

    /// The deck for the current kanji: meaning → stroke → (iPad) write → 음독/훈독/
    /// 그외 word cards (each only if it has words) → (if any) verbs → example.
    private var steps: [Step] {
        var s: [Step] = [.meaning, .stroke]
        if showWrite { s.append(.write) }
        if let k = store.current {
            let g = wordGroups(k)
            if !g.on.isEmpty { s.append(.onWords) }
            if !g.kun.isEmpty { s.append(.kunWords) }
            if !g.other.isEmpty { s.append(.otherWords) }
        }
        if !store.verbs.isEmpty { s.append(.verbs) }
        s.append(.example)
        // Close each kanji with a quick recall quiz (when there's enough material
        // to build one) so the meaning / word sticks before moving on.
        if let k = store.current, studyQuiz(k) != nil { s.append(.quiz) }
        return s
    }

    // MARK: Mixed-in recall quiz

    /// Builds the current kanji's mini-quiz, or nil if there aren't enough
    /// distractors. Odd-position kanji quiz one of their words (memorize related
    /// vocabulary); the rest quiz the kanji's own meaning. Deterministic per
    /// kanji so options don't reshuffle across re-renders.
    private func studyQuiz(_ kanji: Kanji) -> StudyQuizSpec? {
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(kanji.id)))
        let kanjiMeanings = store.queue
            .compactMap { store.content[$0.id]?.glosses }
            .compactMap { localizedGloss($0, appLanguage) }.filter { !$0.isEmpty }
        let vocabMeanings = store.queue
            .flatMap { store.content[$0.id]?.words ?? [] }
            .compactMap { wordMeaning($0, appLanguage) }.filter { !$0.isEmpty }

        // Word-meaning quiz for odd-position kanji that actually have a word.
        if store.index % 2 == 1, let word = store.words.first,
           let answer = wordMeaning(word, appLanguage), !answer.isEmpty {
            let options = quizOptions(answer: answer, pool: vocabMeanings, rng: &rng)
            if options.count >= 2 {
                return StudyQuizSpec(
                    glyph: kanji.literal, wordSurface: word.surface, wordReading: word.reading,
                    prompt: L.studyQuizWordMeaning[appLanguage], options: options, answer: answer)
            }
        }
        // Meaning quiz (default and fallback).
        guard let answer = localizedGloss(store.glosses, appLanguage), !answer.isEmpty else { return nil }
        let options = quizOptions(answer: answer, pool: kanjiMeanings, rng: &rng)
        guard options.count >= 2 else { return nil }
        return StudyQuizSpec(
            glyph: kanji.literal, wordSurface: nil, wordReading: nil,
            prompt: L.studyQuizMeaning[appLanguage], options: options, answer: answer)
    }

    /// The answer plus up to 3 distinct distractors from `pool`, shuffled with a
    /// stable seed. Sorted before shuffling so the base order is deterministic.
    private func quizOptions(answer: String, pool: [String], rng: inout SeededRNG) -> [String] {
        var distractors = Array(Set(pool.filter { $0 != answer })).sorted()
        distractors.shuffle(using: &rng)
        var options = Array(distractors.prefix(3)) + [answer]
        options.shuffle(using: &rng)
        return options
    }
    /// Index of the last card in the deck.
    private var lastCard: Int { max(0, steps.count - 1) }

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
            // Cap the width like the home screen so cards aren't over-wide on
            // iPad / Mac; centered.
            content
                .readableWidth(sizeClass)
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
                // One card at a time (prev·next / arrow keys drive it — no swipe,
                // which also frees the write canvas from a page-swipe conflict).
                // Cards cross-fade + pop instead of sliding.
                ZStack {
                    cardShell { currentCard(kanji) }
                        .id(card)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.90).combined(with: .opacity),
                            removal: .scale(scale: 1.04).combined(with: .opacity)))
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: card)
                // Reset to the first card on a new kanji WITHOUT animating, and
                // clear the previous tracing.
                .onChange(of: store.index) { _, _ in
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { card = 0 }
                    writeDrawing = PKDrawing()
                }
                navButtons
            }
            .padding(16)
            // Hardware-keyboard navigation (iPad / Mac): ← previous, → next.
            .focusable()
            .focused($deckFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { goBack(); return .handled }
            .onKeyPress(.rightArrow) { goNext(); return .handled }
            .onAppear { deckFocused = true }
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
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= min(card, lastCard) ? Palette.pink : Palette.pinkSoft)
                        .frame(height: 5)
                }
            }
        }
    }

    /// The card for the current step (from the dynamic `steps` deck).
    @ViewBuilder
    private func currentCard(_ kanji: Kanji) -> some View {
        switch steps[min(card, lastCard)] {
        case .meaning: meaningCard(kanji)
        case .stroke: strokeCard(kanji)
        case .write: writeCard(kanji)
        case .onWords:
            wordGroupCard(L.worksheetOnWords[appLanguage], Palette.sky, wordGroups(kanji).on)
        case .kunWords:
            wordGroupCard(L.worksheetKunWords[appLanguage], Palette.mint, wordGroups(kanji).kun)
        case .otherWords:
            wordGroupCard(L.worksheetOtherWords[appLanguage], Palette.lavender, wordGroups(kanji).other)
        case .verbs: verbsCard
        case .example: exampleCard
        case .quiz:
            if let spec = studyQuiz(kanji) { StudyQuizCard(spec: spec, language: appLanguage) }
        }
    }

    /// Centers a card in the available space. No scrolling — each card's content
    /// is kept short enough to fit (lists are split across cards and capped).
    private func cardShell<Content: View>(@ViewBuilder _ body: @escaping () -> Content) -> some View {
        body()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        // A wide symmetric ambient halo (radiates on every side) plus a faint
        // grounding shadow — soft all around, not a hard band below.
        .shadow(color: accent.opacity(0.10), radius: 30, x: 0, y: 0)
        .shadow(color: accent.opacity(0.09), radius: 16, x: 0, y: 7)
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

    // MARK: Card 3 — write it yourself (iPad only, 써보기)

    /// A tracing canvas over the faint stroke guide, so the learner writes the
    /// kanji themselves during study. iPad only (Apple Pencil / finger).
    private func writeCard(_ kanji: Kanji) -> some View {
        let side: CGFloat = sizeClass == .compact ? 260 : 320
        return studyCard(L.worksheetWrite[appLanguage], "hand.draw", Palette.butter) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Palette.background)
                    // Trace a faint glyph in the selected Japanese font, so what
                    // you trace matches the kanji shown everywhere else.
                    Text(kanji.literal)
                        .font(.kawaiiJP(side * 0.66, weight: .bold))
                        .japaneseGlyphs()
                        .foregroundStyle(Palette.ink.opacity(0.14))
                    PencilCanvasView(drawing: $writeDrawing).padding(8)
                }
                .frame(width: side, height: side)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Palette.butter.opacity(0.35), lineWidth: 1.5))
                Button { writeDrawing = PKDrawing() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text(L.clear[appLanguage]).font(.kawaii(14, weight: .bold))
                    }
                    .foregroundStyle(Palette.butter)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Palette.butterSoft).clipShape(Capsule())
                }
                .buttonStyle(.bouncy)
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
                .font(.kawaiiJP(16, weight: .semibold)).foregroundStyle(Palette.ink)
        }
    }

    // MARK: 2) Example words — one card per reading (음독 / 훈독 / 그외)

    /// A card of example words that all use the kanji with the same reading kind.
    /// Capped so it fits without scrolling.
    private func wordGroupCard(_ title: String, _ accent: Color, _ words: [WordEntry]) -> some View {
        studyCard(title, "character.book.closed", accent) {
            VStack(spacing: 12) {
                ForEach(words.prefix(5)) { word in wordRow(word, accent) }
            }
        }
    }

    private func wordRow(_ word: WordEntry, _ accent: Color) -> some View {
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
            .background(accent.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.bouncy)
    }

    // MARK: Conjugation — verbs formed with the kanji (활용)

    /// The verbs built from this kanji (e.g. 開く 열리다 / 開ける 열다), so the
    /// learner sees how the same kanji inflects across different verbs. Shown
    /// only when the kanji actually forms verbs (see `steps`).
    @ViewBuilder
    private var verbsCard: some View {
        studyCard(L.worksheetVerbs[appLanguage], "arrow.triangle.branch", Palette.butter) {
            VStack(spacing: 12) {
                ForEach(store.verbs.prefix(5)) { verb in wordRow(verb, Palette.butter) }
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

    private func goBack() { if card > 0 { withAnimation { card -= 1 } } }
    private func goNext() { if card >= lastCard { advance() } else { withAnimation { card += 1 } } }

    /// 이전 · 다음 controls. Also bound to the ← / → keys (iPad/Mac keyboard).
    private var navButtons: some View {
        let finishing = card >= lastCard && store.isLast
        let nextLabel = finishing ? L.done[appLanguage] : L.next[appLanguage]
        let nextColors = finishing ? [Palette.mint, Palette.sky] : [Palette.butter, Palette.pink]
        return HStack(spacing: 12) {
            Button(action: goBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text(L.prev[appLanguage]).font(.kawaii(16, weight: .bold))
                }
                .foregroundStyle(card == 0 ? Palette.inkSoft : Palette.pink)
                .frame(width: 110).padding(.vertical, 14)
                .background(Palette.pinkSoft.opacity(card == 0 ? 0.4 : 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.bouncy)
            .disabled(card == 0)

            Button(action: goNext) {
                Text(nextLabel)
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient(colors: nextColors, startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                    .shadow(color: nextColors[0].opacity(0.4), radius: 10, y: 5)
            }
            .buttonStyle(.bouncy)
        }
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
            Button { store.send(.closeTapped) } label: {
                Text(L.done[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Palette.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 20)
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


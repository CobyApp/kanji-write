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
    @AppStorage("studyStartIndex") private var studyStartIndex = 0
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Which card of the current kanji is showing (0…`lastCard`).
    @State private var card = 0
    /// The learner's tracing on the write card (iPad only). Cleared per kanji.
    @State private var writeDrawing = PKDrawing()
    /// Holds keyboard focus on the deck so ←/→ arrow keys drive prev/next.
    @FocusState private var deckFocused: Bool

    /// The write card (trace over the stroke guide) is part of the deck on every
    /// device — finger tracing works on iPhone too.
    private var showWrite: Bool { true }

    /// The kinds of study card, in deck order. `quiz(i)` is the i-th recall quiz
    /// for the current kanji.
    private enum Step: Equatable { case meaning, stroke, write, onWords, kunWords, otherWords, verbs, example, quiz(Int) }

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
        // Close each kanji with quick recall quizzes (one about the kanji itself,
        // one about a related word) so meaning / readings / vocabulary stick.
        if let k = store.current {
            for i in studyQuizzes(k).indices { s.append(.quiz(i)) }
        }
        return s
    }

    // MARK: Mixed-in recall quizzes

    /// The current kanji's recall quizzes: up to two — one about the kanji itself
    /// (meaning / 음독 / 훈독) and one about a related word (뜻 / 읽기). Rotating
    /// the facet by kanji id gives variety across a session so every aspect gets
    /// exercised. Empty when there isn't enough material for even one.
    private func studyQuizzes(_ kanji: Kanji) -> [StudyQuizSpec] {
        // Two checks per kanji, matched to the active exam: a bank question
        // (읽기·표기·문맥 — shared) + a facet quiz whose candidate set is
        // exam-specific (漢検 adds its staples 画数·部首; JLPT stays vocabulary).
        [bankQuiz(kanji), kanjiFacetQuiz(kanji)].compactMap { $0 }
    }

    /// A pre-authored bank question about the kanji (reading / orthography /
    /// context), shown as a prompt with the target word underlined. Shared by both
    /// exams — 漢検 reads these as 読み / 書き取り, JLPT as 漢字読み / 表記.
    private func bankQuiz(_ kanji: Kanji) -> StudyQuizSpec? {
        guard let q = store.jlptQuestions.first(where: { $0.options.count >= 2 }) else { return nil }
        let label: String
        switch q.kind {
        case "reading": label = L.quizWordReading[appLanguage]
        case "orthography": label = L.quizOrthography[appLanguage]
        default: label = L.quizCloze[appLanguage]
        }
        return StudyQuizSpec(
            subject: .sentence(q.promptClean, focus: q.underlineTarget),
            prompt: label, options: q.options, answer: q.answerText, japaneseOptions: true)
    }

    /// A quiz on the kanji itself: its meaning, 음독, or 훈독 — whichever facets
    /// have data and enough distractors, rotated by kanji id.
    private func kanjiFacetQuiz(_ kanji: Kanji) -> StudyQuizSpec? {
        var rng = SeededRNG(seed: seed(kanji, salt: 1))
        var candidates: [StudyQuizSpec] = []

        // Meaning (options are localized meaning text).
        if let answer = localizedGloss(store.glosses, appLanguage), !answer.isEmpty {
            let pool = store.queue
                .compactMap { store.content[$0.id]?.glosses }
                .compactMap { localizedGloss($0, appLanguage) }
            let options = quizOptions(answer: answer, pool: pool, rng: &rng)
            if options.count >= 2 {
                candidates.append(StudyQuizSpec(
                    subject: .kanji(kanji.literal), prompt: L.studyQuizMeaning[appLanguage],
                    options: options, answer: answer, japaneseOptions: false))
            }
        }
        // 음독 (on) — options are the whole on-reading set of session kanji.
        let on = kanji.onReadings.joined(separator: "、")
        if !on.isEmpty {
            let pool = store.queue.map { $0.onReadings.joined(separator: "、") }
            let options = quizOptions(answer: on, pool: pool, rng: &rng)
            if options.count >= 2 {
                candidates.append(StudyQuizSpec(
                    subject: .kanji(kanji.literal), prompt: L.studyQuizOn[appLanguage],
                    options: options, answer: on, japaneseOptions: true))
            }
        }
        // 훈독 (kun).
        let kun = kanji.kunReadings.joined(separator: "、")
        if !kun.isEmpty {
            let pool = store.queue.map { $0.kunReadings.joined(separator: "、") }
            let options = quizOptions(answer: kun, pool: pool, rng: &rng)
            if options.count >= 2 {
                candidates.append(StudyQuizSpec(
                    subject: .kanji(kanji.literal), prompt: L.studyQuizKun[appLanguage],
                    options: options, answer: kun, japaneseOptions: true))
            }
        }
        // 画数 (stroke count) and 部首 (radical) are 漢検-specific sections — only
        // mix them into the study checks when the learner targets the 漢検.
        if examType == .kanken {
            let unit = L.strokesUnit[appLanguage]
            let answerStrokes = "\(kanji.strokeCount)\(unit)"
            let strokePool = (max(1, kanji.strokeCount - 4)...(kanji.strokeCount + 4))
                .filter { $0 != kanji.strokeCount }.map { "\($0)\(unit)" }
            let strokeOptions = quizOptions(answer: answerStrokes, pool: strokePool, rng: &rng)
            if strokeOptions.count >= 2 {
                candidates.append(StudyQuizSpec(
                    subject: .kanji(kanji.literal), prompt: L.studyQuizStrokes[appLanguage],
                    options: strokeOptions, answer: answerStrokes, japaneseOptions: false))
            }
            if let radical = kanji.radicalGlyph {
                let pool = store.queue.compactMap { $0.radicalGlyph }
                let options = quizOptions(answer: radical, pool: pool, rng: &rng)
                if options.count >= 2 {
                    candidates.append(StudyQuizSpec(
                        subject: .kanji(kanji.literal), prompt: L.studyQuizRadical[appLanguage],
                        options: options, answer: radical, japaneseOptions: true))
                }
            }
        }
        return pick(candidates, kanji)
    }

    /// Deterministically pick one candidate facet for this kanji (rotates the
    /// facet across kanji so a session covers meaning / on / kun / word variety).
    private func pick(_ candidates: [StudyQuizSpec], _ kanji: Kanji) -> StudyQuizSpec? {
        guard !candidates.isEmpty else { return nil }
        return candidates[abs(kanji.id) % candidates.count]
    }

    private func seed(_ kanji: Kanji, salt: UInt64) -> UInt64 {
        UInt64(bitPattern: Int64(kanji.id)) &* 0x9E3779B1 &+ salt
    }

    /// The answer plus up to 3 distinct distractors from `pool`, shuffled with a
    /// stable seed. Sorted before shuffling so the base order is deterministic.
    private func quizOptions(answer: String, pool: [String], rng: inout SeededRNG) -> [String] {
        var distractors = Array(Set(pool.filter { $0 != answer && !$0.isEmpty })).sorted()
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
        .task { store.send(.onAppear(newPerDay: max(1, newPerDay), level: targetLevel, startIndex: studyStartIndex)) }
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
                Text("\(store.deckPosition) / \(store.deckTotal) · \(targetLevel)")
                    .font(.kawaii(14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                // "이미 알아요" — learn the current kanji + jump ahead (start mid-way).
                Button { store.send(.skipTapped) } label: {
                    HStack(spacing: 4) {
                        Text(L.alreadyKnow[appLanguage])
                        Image(systemName: "forward.fill").font(.system(size: 10, weight: .bold))
                    }
                    .font(.kawaii(12, weight: .bold)).foregroundStyle(Palette.lavender)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Palette.lavenderSoft).clipShape(Capsule())
                }
                .buttonStyle(.bouncy)
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
        case let .quiz(i):
            let quizzes = studyQuizzes(kanji)
            if quizzes.indices.contains(i) { StudyQuizCard(spec: quizzes[i], language: appLanguage) }
        }
    }

    /// Centers a card in the available space. No scrolling — each card's content
    /// is kept short enough to fit (lists are split across cards and capped).
    private func cardShell<Content: View>(@ViewBuilder _ body: @escaping () -> Content) -> some View {
        body()
            .frame(maxWidth: .infinity)
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
            VStack(spacing: 14) {
                if !kanji.hasVerifiedStrokeOrder {
                    PastelTile(kanji.literal, soft: Palette.butterSoft, accent: Palette.butter,
                               size: glyphSize, fontSize: glyphSize * 0.62)
                    Text(L.strokeOrderUnavailable[appLanguage])
                        .font(.kawaii(15, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft)
                } else if store.strokePaths.isEmpty {
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
                if kanji.hasVerifiedStrokeOrder {
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
                } else {
                    PastelTile(kanji.literal, soft: Palette.butterSoft, accent: Palette.butter,
                               size: side, fontSize: side * 0.62)
                    Text(L.strokeOrderUnavailable[appLanguage])
                        .font(.kawaii(15, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft)
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


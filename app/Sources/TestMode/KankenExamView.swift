import ComposableArchitecture
import DesignSystem
import PencilKit
import SharedModels
import SwiftUI
import WritingCanvas

/// The exam hub screen: the level's 大問 list, a mock paper and the 오답노트,
/// and — once one is picked — the question player. Readings can be typed and
/// 書き取り written by hand, the way the real 漢検 is answered.
public struct KankenExamView: View {
    @Bindable public var store: StoreOf<KankenExamFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    /// Answer readings by typing and 書き取り by hand, instead of choosing.
    @AppStorage("examWriteMode") private var writeMode = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many questions the mock paper draws from each 大問.
    @State private var perSection = 5

    // Per-question answer input. Reset whenever the question changes.
    @State private var typed = ""
    @State private var drawing = PKDrawing()
    @State private var revealed = false
    @FocusState private var typingFocused: Bool

    /// What a self-marked miss records as the chosen option: never equal to an
    /// answer, and never shown to the learner.
    static let selfMarkedWrong = "\u{0}✗"

    public init(store: StoreOf<KankenExamFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            AuroraBackground()
            if store.isPlaying {
                player
            } else {
                hub
            }
        }
        .task { store.send(.onAppear(level: store.level, language: appLanguage)) }
        .sensoryFeedback(trigger: store.chosen) { _, new in
            guard new != nil else { return nil }
            return store.isCorrect ? .success : .error
        }
    }

    // MARK: - Hub

    private var hub: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                answerModeCard
                mockExamCard
                weakMixCard
                ForEach(examType.sections(for: store.level)) { section in
                    sectionCard(section)
                }
                wrongNoteCard
            }
            .padding(16)
            .readableWidth(sizeClass)
        }
        .scrollIndicators(.hidden)
    }

    /// "JLPT 문제" / "칸켄 문제", per the active exam.
    private var hubTitle: String {
        examType == .kanken ? L.kankenHub[appLanguage] : L.jlptHub[appLanguage]
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(hubTitle)
                .font(.kawaii(24, weight: .bold)).foregroundStyle(Palette.ink)
            // The level used to be fixed to the study plan's; drilling another
            // 級 meant changing the plan. It is a choice here now.
            Menu {
                ForEach(examType.levels, id: \.self) { level in
                    Button {
                        store.send(.levelChanged(level))
                    } label: {
                        if level == store.level {
                            Label(level, systemImage: "checkmark")
                        } else {
                            Text(level)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(store.level)
                        .font(.kawaiiJP(16, weight: .bold)).japaneseGlyphs()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Palette.accent)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .accessibilityLabel("\(L.examLevelPicker[appLanguage]): \(store.level)")
            Text(L.kankenHubSubtitle[appLanguage])
                .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 4)
    }

    private var answerModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.answerMode[appLanguage])
                    .font(.kawaii(13, weight: .bold, language: appLanguage))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                Picker(L.answerMode[appLanguage], selection: $writeMode) {
                    Text(L.answerModeChoice[appLanguage]).tag(false)
                    Text(L.answerModeType[appLanguage]).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            if writeMode {
                Text(L.answerModeHint[appLanguage])
                    .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .roundedCard(padding: 14)
    }

    private func sectionCard(_ section: ExamSection) -> some View {
        Button { store.send(.selectSection(section)) } label: {
            HStack(spacing: 14) {
                Text(section.numeral)
                    .font(.kawaiiJP(20, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.jaTitle)
                        .font(.kawaiiJP(18, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    Text(section.instruction(appLanguage))
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                accuracyBadge(store.state.stat(for: section))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }

    /// First-try accuracy for a section, coloured against the pass line.
    @ViewBuilder
    private func accuracyBadge(_ stat: SectionStat?) -> some View {
        if let stat, stat.attempts > 0 {
            let percent = Int((stat.accuracy * 100).rounded())
            let good = stat.accuracy >= examType.passRatio(for: store.level)
            VStack(spacing: 1) {
                Text("\(percent)%")
                    .font(.kawaii(15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(good ? Palette.mintDeep : Palette.coralDeep)
                Text("\(stat.attempts)\(L.unitQuestions[appLanguage])")
                    .font(.kawaii(10)).monospacedDigit().foregroundStyle(Palette.inkSoft)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 약점 집중 — a mixed drill over the lowest-scoring sections.
    private var weakMixCard: some View {
        let weak = store.state.weakSections
        let tried = weak.contains { store.state.stat(for: $0) != nil }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.weakMix[appLanguage])
                        .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(tried ? L.weakMixSub[appLanguage] : L.weakMixEmpty[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if tried {
                // Which sections the drill will mix, weakest first.
                FlowChips(items: weak.map { section in
                    let stat = store.state.stat(for: section)
                    let score = stat.map { "\(Int(($0.accuracy * 100).rounded()))%" } ?? L.notTriedYet[appLanguage]
                    return "\(section.jaTitle) \(score)"
                })
                Button { store.send(.selectWeakMix) } label: {
                    Text(L.weakMixStart[appLanguage])
                        .font(.kawaii(15, weight: .bold, language: appLanguage)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Palette.coralDeep).clipShape(Capsule())
                }
                .buttonStyle(.bouncy)
            }
        }
        .roundedCard()
    }

    /// A full paper: every playable 大問 at this level, back to back, scored
    /// against the level's pass line. It leads the hub because sitting the
    /// whole thing is a different exercise from drilling one section.
    private var mockExamCard: some View {
        let playable = examType.sections(for: store.level).filter(\.available).count
        let passPercent = Int((examType.passRatio(for: store.level) * 100).rounded())
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.lavender)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.mockExam[appLanguage])
                        .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(L.mockExamSub[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 8) {
                infoPill(icon: "flag.checkered",
                         text: "\(examType.hasOfficialPassLine ? L.examPassLine[appLanguage] : L.examGuideLine[appLanguage]) \(passPercent)%")
                infoPill(icon: "timer",
                         text: "\(L.timeLimit[appLanguage]) \(L.clock(perSection * playable * KankenExamFeature.secondsPerQuestion))")
                if let minutes = examType.officialMinutes(for: store.level) {
                    infoPill(icon: "clock",
                             text: "\(L.examOfficialTime[appLanguage]) \(minutes)\(L.minutesUnit[appLanguage])")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // How long a sitting: the total is this times the playable sections,
            // so it is shown rather than left to be worked out.
            VStack(spacing: 6) {
                HStack {
                    Text(L.mockExamSize[appLanguage])
                        .font(.kawaii(12, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text("\(perSection * playable)\(L.unitQuestions[appLanguage])")
                        .font(.kawaii(13, weight: .bold)).foregroundStyle(Palette.ink)
                }
                Picker(L.mockExamSize[appLanguage], selection: $perSection) {
                    ForEach([3, 5, 10], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Button { store.send(.selectMockExam(perSection: perSection)) } label: {
                Text(L.mockExamStart[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient(colors: [Palette.lavender, Palette.sky],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.bouncy)
            .disabled(playable == 0)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.06), radius: 8, y: 3)
    }

    private func infoPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.kawaii(12, weight: .bold, language: appLanguage))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Palette.lavenderSoft)
        .clipShape(Capsule())
    }

    private var wrongNoteCard: some View {
        Button { store.send(.selectWrongNote) } label: {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.wrongNote[appLanguage])
                        .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(store.wrongCount == 0 ? L.wrongNoteDesc[appLanguage]
                                               : store.wrongDue > 0
                                                 ? "\(L.wrongDueToday[appLanguage]) \(store.wrongDue) · \(L.wrongNoteSpaced[appLanguage])"
                                                 : L.wrongNoteSpaced[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if store.wrongCount > 0 {
                    Text("\(store.wrongCount)")
                        .font(.kawaii(14, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.pink).clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                }
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
        .disabled(store.wrongCount == 0)
    }

    // MARK: - Player

    @ViewBuilder
    private var player: some View {
        VStack(spacing: 0) {
            if store.isLoading {
                loadingCard
            } else if store.isFinished {
                ScrollView {
                    resultCard
                        .readableWidth(sizeClass)
                }
                .scrollIndicators(.hidden)
            } else if let item = store.current {
                ScrollView {
                    VStack(spacing: 20) {
                        progress
                        questionCard(item)
                        answerArea(item)
                        if store.answered { explanationCard(item); nextButton }
                    }
                    .padding(16)
                    .readableWidth(sizeClass)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
                               value: store.answered)
                    .animation(reduceMotion ? nil : .easeInOut, value: store.current?.id)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            } else {
                emptyCard
            }
        }
        .onChange(of: store.attempt) { _, _ in
            typed = ""
            drawing = PKDrawing()
            revealed = false
            if let item = store.current, canType(item) { typingFocused = true }
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Palette.accent)
            Text(L.loadingQuestions[appLanguage])
                .font(.kawaii(15, language: appLanguage)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The one top strip during a section: the section title, the progress
    /// count and a progress bar. Exiting is the session's ✕ (top-left).
    private var progress: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(store.sessionTitle)
                    .font(.kawaiiJP(15, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let limit = store.timeLimit, let started = store.startedAt {
                    countdown(limit: limit, started: started)
                }
                Text("\(store.progressCount) / \(store.total)")
                    .font(.kawaii(15, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
            }
            ProgressView(value: Double(store.progressCount), total: Double(max(store.total, 1)))
                .tint(Palette.accent)
        }
        .roundedCard()
        .accessibilityElement(children: .combine)
    }

    /// Remaining time on a mock paper; turns red in the last minute.
    private func countdown(limit: Int, started: Date) -> some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            let left = max(0, limit - Int(context.date.timeIntervalSince(started)))
            Label(L.clock(left), systemImage: "timer")
                .font(.kawaii(14, weight: .bold)).monospacedDigit()
                .foregroundStyle(left <= 60 ? Palette.pinkDeep : Palette.ink)
                .accessibilityLabel("\(L.timeLeft[appLanguage]) \(L.clock(left))")
        }
    }

    private func questionCard(_ item: KankenQuestion) -> some View {
        VStack(spacing: 10) {
            Text(item.label ?? item.type.instruction(appLanguage))
                .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let paths = item.strokePaths, let marked = item.markedStroke {
                // 筆順 cannot be asked in text: the question is "this stroke,
                // where does it come?", so the stroke has to be pointed at.
                MarkedStrokeGlyph(paths: paths, marked: marked)
                    .frame(maxWidth: 200).aspectRatio(1, contentMode: .fit)
            } else {
                // Generated prompts carry a gloss on a second line — the reading
                // under an idiom, the meaning under a 送りがな word. It is a
                // hint, not the question, so it is set small.
                let lines = item.prompt.components(separatedBy: "\n")
                let head = KankenQuestion(
                    id: item.id, type: item.type, kanjiID: item.kanjiID,
                    prompt: lines[0], focus: item.focus, options: item.options,
                    answer: item.answer)
                promptText(head)
                    .font(.kawaiiJP(promptSize(lines[0]), weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if lines.count > 1 {
                    Text(lines.dropFirst().joined(separator: "\n"))
                        .font(.kawaii(16, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .roundedCard()
    }

    private func promptText(_ item: KankenQuestion) -> Text {
        guard let focus = item.focus, !focus.isEmpty,
              let range = item.prompt.range(of: focus) else { return Text(item.prompt) }
        let before = String(item.prompt[..<range.lowerBound])
        let target = String(item.prompt[range])
        let after = String(item.prompt[range.upperBound...])
        return Text(before)
            + Text(target).underline().foregroundColor(Palette.accent)
            + Text(after)
    }

    private func promptSize(_ prompt: String) -> CGFloat {
        let longestLine = prompt.split(separator: "\n").map(\.count).max() ?? prompt.count
        switch longestLine { case 0...3: return 44; case 4...10: return 30; default: return 22 }
    }

    // MARK: Answer input

    /// Kana-only answers can be typed: the real 読み section is written, not chosen.
    private func canType(_ item: KankenQuestion) -> Bool {
        writeMode && item.type == .reading && !item.answer.isEmpty
            && item.answer.unicodeScalars.allSatisfy { Self.isKana($0) }
    }

    /// 書き取り / 表記 can be written by hand, then checked against the answer.
    private func canHandwrite(_ item: KankenQuestion) -> Bool {
        writeMode && item.type == .writing
            && (item.sectionID == "writing" || item.sectionID == "orthography")
    }

    @ViewBuilder
    private func answerArea(_ item: KankenQuestion) -> some View {
        if canType(item) {
            typedAnswer(item)
        } else if canHandwrite(item) {
            handwrittenAnswer(item)
        } else {
            options(item)
        }
    }

    private func typedAnswer(_ item: KankenQuestion) -> some View {
        VStack(spacing: 12) {
            TextField(L.typeReadingPlaceholder[appLanguage], text: $typed)
                .font(.kawaiiJP(24, weight: .bold)).japaneseGlyphs()
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($typingFocused)
                .submitLabel(.done)
                .onSubmit { submitTyped(item) }
                .padding(.vertical, 16).padding(.horizontal, 12)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(typedStroke(item), lineWidth: 2))
                .disabled(store.answered)
            if !store.answered {
                primaryButton(L.checkAnswer[appLanguage]) { submitTyped(item) }
                    .disabled(Self.normalizeKana(typed).isEmpty)
            }
        }
        .onAppear { typingFocused = true }
    }

    private func submitTyped(_ item: KankenQuestion) {
        let answer = Self.normalizeKana(typed)
        guard !answer.isEmpty, !store.answered else { return }
        typingFocused = false
        store.send(.chose(answer == Self.normalizeKana(item.answer) ? item.answer : answer))
    }

    private func typedStroke(_ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.ink.opacity(0.10) }
        return store.isCorrect ? Palette.mint : Palette.pink
    }

    private func handwrittenAnswer(_ item: KankenQuestion) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                PencilCanvasView(drawing: $drawing)
                    .frame(height: 200)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Palette.ink.opacity(0.10), lineWidth: 2))
                    .allowsHitTesting(!revealed)
                Button { drawing = PKDrawing() } label: {
                    Image(systemName: "eraser")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L.clearCanvas[appLanguage])
                .disabled(revealed)
            }
            if !revealed {
                primaryButton(L.revealAnswer[appLanguage]) { revealed = true }
            } else if !store.answered {
                VStack(spacing: 10) {
                    Text(item.answer)
                        .font(.kawaiiJP(40, weight: .bold)).japaneseGlyphs()
                        .foregroundStyle(Palette.ink)
                    Text(L.selfMarkPrompt[appLanguage])
                        .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    HStack(spacing: 12) {
                        selfMarkButton(L.selfMarkWrong[appLanguage], icon: "xmark",
                                       color: Palette.pink) {
                            store.send(.chose(Self.selfMarkedWrong))
                        }
                        selfMarkButton(L.selfMarkRight[appLanguage], icon: "checkmark",
                                       color: Palette.mint) {
                            store.send(.chose(item.answer))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .roundedCard()
            }
        }
    }

    private func selfMarkButton(_ title: String, icon: String, color: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.kawaii(16, weight: .bold, language: appLanguage))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(color).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }

    /// 用法 answers are sentences, every other 大問's are a word or a reading.
    /// Sizing off the longest option keeps sentences on screen without shrinking
    /// the short answers that most sections use.
    private func optionSize(_ item: KankenQuestion) -> CGFloat {
        let longest = item.options.map(\.count).max() ?? 0
        if longest > 12 { return 15 }
        return item.type == .reading ? 22 : 20
    }

    private func options(_ item: KankenQuestion) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(item.options.enumerated()), id: \.element) { index, option in
                Button { store.send(.chose(option)) } label: {
                    HStack(spacing: 12) {
                        Text(["ア", "イ", "ウ", "エ", "オ", "カ"][min(index, 5)])
                            .font(.kawaiiJP(14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                        Text(option)
                            .font(.kawaiiJP(optionSize(item), weight: .bold)).japaneseGlyphs()
                            .foregroundStyle(optionText(option, item)).multilineTextAlignment(.leading)
                            // 用法's options are whole sentences; without this the
                            // HStack gives them one line and clips the rest.
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if store.answered, option == item.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mintDeep)
                        } else if store.answered, option == store.chosen {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.pinkDeep)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(optionFill(option, item))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(optionStroke(option, item), lineWidth: 2))
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.answered)
                .accessibilityValue(accessibilityState(option, item))
            }
        }
    }

    private func accessibilityState(_ option: String, _ item: KankenQuestion) -> String {
        guard store.answered else { return "" }
        if option == item.answer { return L.quizCorrect[appLanguage] }
        if option == store.chosen { return L.quizWrong[appLanguage] }
        return ""
    }

    @ViewBuilder
    private func explanationCard(_ item: KankenQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: store.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(store.isCorrect ? L.quizCorrect[appLanguage] : L.quizWrong[appLanguage])
                    .font(.kawaii(15, weight: .bold))
            }
            .foregroundStyle(store.isCorrect ? Palette.mintDeep : Palette.pinkDeep)
            // A typed answer that was wrong isn't one of the options, so it
            // isn't marked anywhere else; show it next to the right one.
            if !store.isCorrect, let chosen = store.chosen, chosen != Self.selfMarkedWrong,
               !item.options.contains(chosen) {
                Text("\(L.yourAnswer[appLanguage]): \(chosen)　→　\(item.answer)")
                    .font(.kawaiiJP(16, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink)
            }
            if let explanation = item.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundedCard()
        .accessibilityElement(children: .combine)
    }

    private var nextButton: some View {
        primaryButton(L.next[appLanguage]) { store.send(.next) }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Palette.accent).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }

    // MARK: Results

    @ViewBuilder
    private var resultCard: some View {
        VStack(spacing: 16) {
            if store.isWrongNote {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48)).foregroundStyle(Palette.mint)
                Text(L.wrongNoteCleared[appLanguage])
                    .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            } else if store.isMockExam {
                if let limit = store.timeLimit, store.elapsedSeconds >= limit {
                    Label(L.timeUp[appLanguage], systemImage: "timer")
                        .font(.kawaii(13, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.pinkDeep)
                        .multilineTextAlignment(.center)
                }
                mockResult
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48)).foregroundStyle(Palette.mint)
                Text(L.examPracticeDone[appLanguage])
                    .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
                statRow(L.examFirstTry[appLanguage],
                        "\(Int((store.scoreRatio * 100).rounded()))%  (\(store.firstTryCorrect)/\(store.total))")
                statRow(L.examElapsed[appLanguage], L.clock(store.elapsedSeconds))
            }
            if !store.isWrongNote, store.firstTryCorrect < store.total {
                Text(L.examMissedCount[appLanguage])
                    .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button { store.send(.restart) } label: {
                    Text(L.quizAgain[appLanguage])
                        .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Palette.accent).clipShape(Capsule())
                }
                .buttonStyle(.bouncy)
                Button { store.send(.exitToHub) } label: {
                    Text(L.backToHub[appLanguage])
                        .font(.kawaii(16, weight: .bold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Palette.card).clipShape(Capsule())
                        .overlay(Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.bouncy)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 4)
        .roundedCard().padding(16)
    }

    private var mockResult: some View {
        let percent = Int((store.scoreRatio * 100).rounded())
        let passPercent = Int((store.passRatio * 100).rounded())
        return VStack(spacing: 14) {
            Text(L.examMockDone[appLanguage])
                .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            ZStack {
                Circle().stroke(Palette.ink.opacity(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: store.scoreRatio)
                    .stroke(store.passed ? Palette.mint : Palette.coral,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(percent)%")
                        .font(.kawaii(34, weight: .bold)).monospacedDigit().foregroundStyle(Palette.ink)
                    Text("\(store.firstTryCorrect) / \(store.total)")
                        .font(.kawaii(13, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                }
            }
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .combine)

            Text(store.passed ? L.examPassed[appLanguage]
                              : "\(L.examNotYet[appLanguage]) \(max(0, passPercent - percent))%")
                .font(.kawaii(17, weight: .bold, language: appLanguage))
                .foregroundStyle(store.passed ? Palette.mintDeep : Palette.coralDeep)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                statRow(ExamType.current.hasOfficialPassLine ? L.examPassLine[appLanguage]
                                                             : L.examGuideLine[appLanguage],
                        "\(passPercent)%")
                statRow(L.examElapsed[appLanguage], L.clock(store.elapsedSeconds))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L.examBySection[appLanguage])
                    .font(.kawaii(14, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                ForEach(store.sectionTallies) { tally in
                    sectionBar(tally)
                }
            }
            .padding(14)
            .background(Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func sectionBar(_ tally: KankenExamFeature.SectionTally) -> some View {
        let ratio = tally.total > 0 ? Double(tally.correct) / Double(tally.total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tally.title)
                    .font(.kawaiiJP(14, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("\(tally.correct)/\(tally.total)")
                    .font(.kawaii(13, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
            }
            ProgressView(value: ratio)
                .tint(ratio >= store.passRatio ? Palette.mint : Palette.coral)
        }
        .accessibilityElement(children: .combine)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(value)
                .font(.kawaii(15, weight: .bold)).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: 320)
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: store.isWrongNote ? "checkmark.seal.fill" : "tray")
                .font(.system(size: 44)).foregroundStyle(store.isWrongNote ? Palette.mint : Palette.inkSoft)
            Text(store.isWrongNote ? L.wrongNoteEmpty[appLanguage] : L.kankenSectionEmpty[appLanguage])
                .font(.kawaii(16, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
            Button { store.send(.exitToHub) } label: {
                Text(L.backToHub[appLanguage])
                    .font(.kawaii(15, weight: .bold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Palette.card).clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .roundedCard().padding(16)
    }

    // Option styling: neutral until answered, then green (correct) / red (chosen wrong).
    private func optionText(_ option: String, _ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.ink }
        if option == item.answer { return Palette.mintDeep }
        if option == store.chosen { return Palette.pinkDeep }
        return Palette.inkSoft
    }
    private func optionFill(_ option: String, _ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.card }
        if option == item.answer { return Palette.mintSoft }
        if option == store.chosen { return Palette.pinkSoft }
        return Palette.card
    }
    private func optionStroke(_ option: String, _ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.ink.opacity(0.08) }
        if option == item.answer { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Color.clear
    }

    // MARK: Kana helpers

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
    }

    /// Hiragana, no spaces: typed ヒトツ, ひとつ and " ひとつ " all match ひとつ.
    static func normalizeKana(_ text: String) -> String {
        let trimmed = text.filter { !$0.isWhitespace }
        return trimmed.applyingTransform(.hiraganaToKatakana, reverse: true) ?? trimmed
    }
}


/// Small wrapping chips — the weak-spot sections.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.kawaiiJP(13, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.coralDeep)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Palette.coralSoft).clipShape(Capsule())
            }
        }
    }
}

/// A minimal left-to-right wrapping layout.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

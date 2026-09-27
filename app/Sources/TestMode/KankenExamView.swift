import ComposableArchitecture
import DesignSystem
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
            // The real-format paper is marked only at the end; a buzz per
            // answer would mark it as it goes.
            guard new != nil, !store.isRealExam else { return nil }
            return store.isCorrect ? .success : .error
        }
    }

    // MARK: - Hub

    private var hub: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                answerModeCard
                if examType == .kanken, let paper = KankenPaper.official(for: store.level) {
                    realExamCard(paper)
                }
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(section.jaTitle)
                            .font(.kawaiiJP(18, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                        if let name = section.localizedName(appLanguage) {
                            Text(name)
                                .font(.kawaii(13, weight: .bold, language: appLanguage))
                                .foregroundStyle(Palette.accent)
                        }
                    }
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
                Text(L.questionCount(stat.attempts, appLanguage))
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
                    Text(L.questionCount(perSection * playable, appLanguage))
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

    /// 실전 모의고사: the level's paper as the real 漢検 prints it — every 大問
    /// at its official size and points, the official time, scored in points
    /// against the official pass mark, and no marking until the end.
    private func realExamCard(_ paper: KankenPaper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(L.realExam[appLanguage]) · \(paper.level)")
                        .font(.kawaii(17, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                    Text(L.realExamSub[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 8) {
                infoPill(icon: "rosette",
                         text: "\(L.paperTotal[appLanguage]) \(paper.total)\(L.points[appLanguage])")
                infoPill(icon: "flag.checkered",
                         text: "\(L.passMark[appLanguage]) \(paper.pass)\(L.points[appLanguage])")
                infoPill(icon: "clock", text: "\(paper.minutes)\(L.minutesUnit[appLanguage])")
                infoPill(icon: "list.number", text: L.questionCount(paper.questionCount, appLanguage))
            }

            // The paper's 大問 at a glance: marker, name, points × count.
            VStack(spacing: 4) {
                ForEach(paper.parts) { part in
                    HStack(spacing: 8) {
                        Text(KankenPaper.numeral(part.index))
                            .font(.kawaiiJP(12, weight: .bold)).foregroundStyle(Palette.coralDeep)
                            .frame(width: 26, alignment: .leading)
                        Text(part.title)
                            .font(.kawaiiJP(13, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 6)
                        Text("\(part.points)×\(part.count) = \(part.maxPoints)")
                            .font(.kawaii(12)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .background(Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button { store.send(.selectRealExam) } label: {
                Text(L.realExamStart[appLanguage])
                    .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient(colors: [Palette.coral, Palette.pink],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.bouncy)
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
                if store.isRealExam, let points = store.current?.points {
                    Text("\(points)\(L.points[appLanguage])")
                        .font(.kawaii(11, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.coralDeep)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Palette.coral.opacity(0.15)).clipShape(Capsule())
                }
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
                ExamPromptText(prompt: item.prompt, focus: item.focus, language: appLanguage)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .roundedCard()
    }

    // MARK: Answer input

    /// Kana-only answers can be typed: the real 読み section is written, not chosen.
    private func canType(_ item: KankenQuestion) -> Bool {
        writeMode && item.type == .reading && ExamKana.isKanaOnly(item.answer)
    }

    /// 書き取り / 表記 can be written by hand, then checked against the answer.
    private func canHandwrite(_ item: KankenQuestion) -> Bool {
        writeMode && item.type == .writing
            && (item.sectionID == "writing" || item.sectionID == "orthography")
    }

    /// Keyed by the attempt, so a fresh attempt starts from an empty field or
    /// canvas even when the same question comes straight back.
    @ViewBuilder
    private func answerArea(_ item: KankenQuestion) -> some View {
        Group {
            if canType(item) {
                TypedReadingAnswer(answer: item.answer, chosen: store.chosen, language: appLanguage,
                                   submitTitle: store.isRealExam ? L.next[appLanguage] : nil) {
                    store.send(.chose($0))
                }
            } else if canHandwrite(item) {
                HandwrittenAnswer(answer: item.answer, answered: store.answered, language: appLanguage) {
                    store.send(.chose($0 ? item.answer : ExamKana.selfMarkedWrong))
                }
            } else {
                ExamOptionList(options: item.options, answer: item.answer, chosen: store.chosen,
                               isReading: item.type == .reading, language: appLanguage) {
                    store.send(.chose($0))
                }
            }
        }
        .id(store.attempt)
    }

    private func explanationCard(_ item: KankenQuestion) -> some View {
        ExamExplanationCard(isCorrect: store.isCorrect, chosen: store.chosen, options: item.options,
                            answer: item.answer, explanation: item.explanation, language: appLanguage)
    }

    private var nextButton: some View {
        ExamPrimaryButton(title: L.next[appLanguage], language: appLanguage) { store.send(.next) }
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
        return Group {
            if store.isRealExam { realResult } else { shortMockResult(percent, passPercent) }
        }
    }

    /// A real-format paper's result: points out of the paper's total against
    /// its pass mark, per 大問, and every miss to look back over.
    private var realResult: some View {
        let ratio = store.maxPoints > 0 ? Double(store.earnedPoints) / Double(store.maxPoints) : 0
        return VStack(spacing: 14) {
            Text(L.realExamDone[appLanguage])
                .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            ZStack {
                Circle().stroke(Palette.ink.opacity(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(store.passed ? Palette.mint : Palette.coral,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(store.earnedPoints)")
                        .font(.kawaii(38, weight: .bold)).monospacedDigit().foregroundStyle(Palette.ink)
                    Text("/ \(store.maxPoints)\(L.points[appLanguage])")
                        .font(.kawaii(13, weight: .bold, language: appLanguage)).monospacedDigit()
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .combine)

            Text(store.passed ? L.realExamPassed[appLanguage]
                              : L.belowPassPoints(store.passPoints - store.earnedPoints, appLanguage))
                .font(.kawaii(17, weight: .bold, language: appLanguage))
                .foregroundStyle(store.passed ? Palette.mintDeep : Palette.coralDeep)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                statRow(L.passMark[appLanguage],
                        "\(store.passPoints) / \(store.maxPoints)\(L.points[appLanguage])")
                statRow(L.examFirstTry[appLanguage], "\(store.firstTryCorrect) / \(store.total)")
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

            if !store.missedItems.isEmpty { missedReview }
        }
    }

    /// The paper is marked only at the end, so this is where the learner
    /// sees what they got wrong: their answer, the right one, and why.
    private var missedReview: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.missedItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        if let index = item.partIndex {
                            Text(store.sectionTitles["p\(index)"] ?? "")
                                .font(.kawaiiJP(11, weight: .bold)).foregroundStyle(Palette.coralDeep)
                        }
                        Text(item.prompt.components(separatedBy: "\n")[0])
                            .font(.kawaiiJP(15, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let chosen = store.chosenAnswers[item.id],
                           chosen != ExamKana.selfMarkedWrong {
                            Text("\(L.yourAnswer[appLanguage]): \(chosen)")
                                .font(.kawaiiJP(13)).japaneseGlyphs().foregroundStyle(Palette.pinkDeep)
                        }
                        Text("\(L.correctAnswer[appLanguage]): \(item.answer)")
                            .font(.kawaiiJP(13, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.mintDeep)
                        if let explanation = item.explanation, !explanation.isEmpty {
                            Text(explanation)
                                .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 8)
        } label: {
            Text(L.reviewMissed(store.missedItems.count, appLanguage))
                .font(.kawaii(14, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
        }
        .tint(Palette.ink)
        .padding(14)
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shortMockResult(_ percent: Int, _ passPercent: Int) -> some View {
        VStack(spacing: 14) {
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
                              : L.belowPassLine(max(0, passPercent - percent), appLanguage))
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
                if let earned = tally.earnedPoints, let worth = tally.maxPoints {
                    Text("\(earned)/\(worth)\(L.points[appLanguage])")
                        .font(.kawaii(13, weight: .bold, language: appLanguage)).monospacedDigit()
                        .foregroundStyle(Palette.inkSoft)
                } else {
                    Text("\(tally.correct)/\(tally.total)")
                        .font(.kawaii(13, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                }
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

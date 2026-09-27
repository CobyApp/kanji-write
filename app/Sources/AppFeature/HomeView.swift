import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI
import WidgetKit

/// The single Home dashboard — every feature on one scrolling screen: progress
/// ring, study plan (level + date range → daily goal), the three study-mode
/// launchers (learn / review / practice), a dictionary entry, and a bookmarks
/// preview. Details push; sessions cover; settings is a sheet (toolbar gear).
struct HomeView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    // Study-plan start position: how many kanji to skip at the front of the level.
    @AppStorage("studyStartIndex") private var studyStartIndex = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPlan = false
    @State private var wordbookTab = 0          // 0: 한자, 1: 단어
    @State private var flashcards: [FlashcardItem] = []   // non-empty → card session shown
    /// The saved words' own spaced-repetition review (built, never reachable).
    @State private var showWordReview = false

    private var levelOrder: [Kanji] { studyOrder(store.review.kanji.elements, exam: examType, level: targetLevel) }
    private var learnedInLevel: Int {
        let tracked = Set(store.review.records.ids)
        // Kanji before the plan's start position count as already known (the
        // learner chose to skip them), so they fill the progress ring too.
        let skipped = min(max(0, studyStartIndex), levelOrder.count)
        let learnedAfter = levelOrder.dropFirst(skipped).filter { tracked.contains($0.id) }.count
        return skipped + learnedAfter
    }
    private var levelTotal: Int { max(levelOrder.count, 1) }
    private var progress: Double { Double(learnedInLevel) / Double(levelTotal) }

    /// Every kanji in the current level (from the plan's start) has been learned.
    private var levelComplete: Bool { !levelOrder.isEmpty && remaining == 0 }
    /// The next 급수/level after the current one, if any (nil at the last level).
    private var nextLevel: String? {
        let levels = examType.levels
        guard let i = levels.firstIndex(of: targetLevel), i + 1 < levels.count else { return nil }
        return levels[i + 1]
    }
    /// Advance the plan to the next level and start it from the beginning.
    private func advanceLevel() {
        guard let next = nextLevel else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            targetLevel = next
            studyStartIndex = 0
        }
    }
    private var session: StudySession {
        todaysSession(records: store.review.records.elements, order: levelOrder,
                      today: store.review.today, newPerDay: newPerDay, startIndex: studyStartIndex)
    }

    // Plan: the daily new-kanji count is the source of truth; the goal date is
    // derived from it (finish the level's remaining kanji at this rate). Editing
    // the goal date translates back into a daily count, so the two fields in the
    // plan editor always stay in sync — change either, the other follows.
    private var goalDays: Int { daysToFinish(remaining: max(1, remaining), perDay: newPerDay) }
    private var goalDate: Date {
        Calendar.current.date(byAdding: .day, value: goalDays,
                              to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
    /// Editing the goal date sets the daily count needed to finish by then.
    private var goalDateBinding: Binding<Date> {
        Binding(
            get: { goalDate },
            set: { date in
                let cal = Calendar.current
                let days = max(1, cal.dateComponents(
                    [.day], from: cal.startOfDay(for: Date()),
                    to: cal.startOfDay(for: date)).day ?? 1)
                newPerDay = min(50, max(1, Int((Double(max(1, remaining)) / Double(days)).rounded(.up))))
            })
    }

    private var bookmarkedKanji: [Kanji] {
        let ids = Set(store.bookmarkedIDs)
        return store.review.kanji.elements.filter { ids.contains($0.id) }
    }

    // Streak + today's goal.
    private var streak: Int {
        currentStreak(activeDays: studyDays(records: store.review.records.elements),
                      today: store.review.today)
    }
    private var doneToday: Int { learnedToday(records: store.review.records.elements, today: store.review.today) }
    private var remaining: Int {
        remainingNew(order: levelOrder, records: store.review.records.elements, startIndex: studyStartIndex)
    }

    /// Today's goal grows in `newPerDay` steps as you study past it: the target is
    /// the smallest multiple of `newPerDay` that covers what you've done, so the
    /// bar reads 0/20 → 20/20 → 40/40 … and there's always a next target to fill
    /// (never a capped "5/5" or a nonsensical "10/5").
    private var goalTarget: Int {
        guard newPerDay > 0 else { return max(doneToday, 1) }
        let steps = max(1, (doneToday + newPerDay - 1) / newPerDay)
        return steps * newPerDay
    }
    private var goalFraction: Double { goalTarget > 0 ? min(Double(doneToday) / Double(goalTarget), 1) : 0 }

    /// 학습하기 tapped. If today's goal is already met, gate entry behind a
    /// confirmation (pull tomorrow's study forward / take the pending quiz);
    /// otherwise enter study directly.
    private func startStudyTapped() {
        // Below today's goal → finish the remaining quota. Goal already met →
        // seamlessly study ahead with a fresh batch (no repeated confirmation).
        store.send(.startStudy(pullAhead: doneToday >= newPerDay))
    }

    /// The next never-seen kanji in the level (what the widget/watch previews).
    private var nextKanji: Kanji? {
        let tracked = Set(store.review.records.ids)
        return levelOrder.first { !tracked.contains($0.id) }
    }

    /// Publish a compact snapshot to the shared App Group and refresh widgets.
    private func writeSnapshot() {
        let next = nextKanji
        let meaning = next.flatMap { kanjiGloss(store.review.glosses[$0.id] ?? [:], appLanguage) } ?? ""
        let snapshot = StudySnapshot(
            level: targetLevel, dailyGoal: goalTarget, doneToday: doneToday, streak: streak,
            remaining: remaining, learned: learnedInLevel, total: levelTotal,
            nextGlyph: next?.literal ?? "", nextMeaning: meaning, language: appLanguage.rawValue)
        StudySnapshotStore.save(snapshot)          // → home-screen widget (App Group)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchSync.shared.send(snapshot)       // → Apple Watch (no-op on Catalyst)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            FloatingBlobs()
            ScrollView {
                Group {
                    if sizeClass == .compact {
                        compactLayout.readableWidth(sizeClass)
                    } else {
                        // A wide iPad / Mac window gets two panes; anything
                        // narrower keeps the single centred column.
                        ViewThatFits(in: .horizontal) {
                            padLandscapeLayout
                                .frame(minWidth: 1000, maxWidth: 1280)
                                .frame(maxWidth: .infinity)
                            padPortraitLayout.readableWidth(sizeClass)
                        }
                    }
                }
                .padding(.horizontal, sizeClass == .compact ? 22 : 34)
                .padding(.top, 22)
                .padding(.bottom, 56)
            }
            .scrollIndicators(.hidden)
            // Settings opens from a round button aligned to the top-right of the
            // capped content (not the screen edge). Same CircleButton style as
            // every close ✕; in-content so it responds on Mac Catalyst.
            VStack {
                HStack {
                    Spacer()
                    CircleButton("gearshape") { store.send(.setShowSettings(true)) }
                        .accessibilityLabel(L.settings[appLanguage])
                }
                .padding(.horizontal, sizeClass == .compact ? 22 : 34)
                .readableWidth(sizeClass)
                Spacer()
            }
            .padding(.top, 22)
            // The plan editor is a full-screen in-app overlay (same style as
            // settings). In-content buttons respond reliably on Mac Catalyst.
            if showPlan { planOverlay.zIndex(1) }
            if store.showWordbook { wordbookOverlay.zIndex(1) }
            if showWordReview { wordReviewOverlay.zIndex(1.5) }
            if !flashcards.isEmpty {
                FlashcardView(items: flashcards) { flashcards = [] }
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: flashcards.isEmpty)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Keep the plan's level valid for the current exam (guards against a
            // stale JLPT level lingering after switching to 漢検, or vice versa).
            if !examType.levels.contains(targetLevel) { targetLevel = examType.defaultLevel }
            store.send(.bookmarksAppeared)
            store.send(.wordReview(.onAppear))
            store.send(.refreshWrongDue(level: targetLevel))
            writeSnapshot()
        }
        .onChange(of: examType) { _, newExam in
            if !newExam.levels.contains(targetLevel) {
                targetLevel = newExam.defaultLevel
                studyStartIndex = 0
            }
        }
        .onChange(of: newPerDay) { _, _ in writeSnapshot() }
        .onChange(of: targetLevel) { _, level in
            studyStartIndex = 0
            writeSnapshot()
            store.send(.refreshWrongDue(level: level))
        }
        .onChange(of: levelTotal) { _, _ in writeSnapshot() }
        .onChange(of: store.review.records.count) { _, _ in writeSnapshot() }
    }

    private func closePlan() { withAnimation(.easeOut(duration: 0.18)) { showPlan = false } }

    /// The study-plan editor as a full-screen overlay with the shared header
    /// (✕ top-left + title) — the same presentation as settings.
    private var planOverlay: some View {
        ScrollView {
            planEditor
                .padding(20)
                .readableWidth(sizeClass)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) {
            OverlayHeader(title: L.studyPlan[appLanguage]) { closePlan() }
        }
        .background(Palette.background.ignoresSafeArea())
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    // MARK: Greeting + ring

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.greeting[appLanguage])
                .font(.kawaii(24, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
            // Which exam you are on used to be visible only inside Settings.
            // Tapping the chip opens the plan, where exam and level both live.
            Button { withAnimation(.easeOut(duration: 0.18)) { showPlan = true } } label: {
                HStack(spacing: 6) {
                    Text(examType == .kanken ? "漢検" : "JLPT")
                        .font(.kawaiiJP(13, weight: .bold)).japaneseGlyphs()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.accent).clipShape(Capsule())
                    Text("\(targetLevel) · \(learnedInLevel)/\(levelTotal)")
                        .font(.kawaii(14)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.inkSoft)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L.studyPlan[appLanguage]): \(examType == .kanken ? "漢検" : "JLPT") \(targetLevel)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ring(_ size: CGFloat) -> some View {
        ProgressRing(progress: progress, size: size, lineWidth: size > 160 ? 18 : 15) {
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.kawaii(size > 160 ? 38 : 30, weight: .bold)).foregroundStyle(Palette.ink)
                Text(targetLevel).font(.kawaii(14, weight: .bold)).foregroundStyle(Palette.pink)
            }
        }
    }

    // MARK: Adaptive layouts

    /// iPhone: a single column mirroring the iPad flow — ring centered on top,
    /// the streak/goal chips in a row beneath it, then plan and launchers.
    @ViewBuilder private var compactLayout: some View {
        VStack(spacing: 20) {
            greeting.popIn(delay: 0.02)
            ring(168).popIn(delay: 0.08)
            HStack(spacing: 12) { streakChip; goalChip }.popIn(delay: 0.12)
            planButton.popIn(delay: 0.16)
            if levelComplete { levelCompleteCard.popIn(delay: 0.18) }
            // iPhone is a single narrow column — every launcher is a full-width
            // row, grouped by purpose so eight tiles don't read as one flat list.
            VStack(spacing: 22) {
                launcherSection(L.sectionStudy[appLanguage], Palette.pink) {
                    studyLauncher; reviewLauncher
                    if store.wrongDue > 0 { wrongNoteLauncher }
                    kankenButton
                }
                launcherSection(L.sectionTests[appLanguage], Palette.butter) {
                    practiceButton
                    favoritesButton
                }
                launcherSection(L.sectionDictionaries[appLanguage], Palette.sky) {
                    dictionaryButton
                    wordDictionaryButton
                    expressionDictionaryButton
                    if examType == .kanken { yojiDictionaryButton }
                }
                launcherSection(L.sectionCollection[appLanguage], Palette.teal) {
                    statsButton
                    wordbookButton
                }
            }
            .popIn(delay: 0.22)
        }
    }

    /// iPad portrait: a centered column — ring + stats on top, plan below full
    /// width, launchers in a 2-up grid. (Taller than it is wide, so no side panes.)
    @ViewBuilder private var padPortraitLayout: some View {
        VStack(spacing: 24) {
            greeting.popIn(delay: 0.02)
            ring(200).popIn(delay: 0.08)
            HStack(spacing: 12) { streakChip; goalChip }.popIn(delay: 0.12)
            planButton.popIn(delay: 0.16)
            if levelComplete { levelCompleteCard.popIn(delay: 0.18) }
            launchersGrid.popIn(delay: 0.22)
        }
    }

    /// iPad landscape / wide Mac window: progress on the left, every launcher
    /// on the right — the single column left most of a landscape screen empty.
    @ViewBuilder private var padLandscapeLayout: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(spacing: 22) {
                greeting.popIn(delay: 0.02)
                ring(220).popIn(delay: 0.08)
                HStack(spacing: 12) { streakChip; goalChip }.popIn(delay: 0.12)
                planButton.popIn(delay: 0.16)
                if levelComplete { levelCompleteCard.popIn(delay: 0.18) }
            }
            .frame(width: 380)
            launchersGrid.popIn(delay: 0.22)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Streak + today's goal chips

    private var streakChip: some View {
        VStack(spacing: 4) {
            Text("\(streak)").font(.kawaii(26, weight: .bold)).foregroundStyle(Palette.butter)
                .contentTransition(.numericText()).animation(.snappy, value: streak)
            Text(L.streak[appLanguage]).font(.kawaii(12)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Palette.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 5, y: 2)
    }

    private var goalChip: some View {
        VStack(spacing: 6) {
            Text("\(doneToday)/\(goalTarget)")
                .font(.kawaii(20, weight: .bold)).monospacedDigit().foregroundStyle(Palette.mint)
                .contentTransition(.numericText()).animation(.snappy, value: doneToday)
            Capsule().fill(Palette.mintSoft).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.mint, Palette.sky],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * goalFraction)
                    }
                }
                .frame(height: 6).padding(.horizontal, 10)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: goalFraction)
            Text(L.todayGoal[appLanguage]).font(.kawaii(12)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Palette.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 5, y: 2)
    }

    /// The four launchers as a 2-column grid (iPad).
    private var launchersGrid: some View {
        VStack(spacing: 22) {
            launcherSection(L.sectionStudy[appLanguage], Palette.pink, grid: true) {
                studyLauncher; reviewLauncher
                if store.wrongDue > 0 { wrongNoteLauncher }
                kankenButton
            }
            launcherSection(L.sectionTests[appLanguage], Palette.butter, grid: true) {
                practiceButton
                favoritesButton
            }
            launcherSection(L.sectionDictionaries[appLanguage], Palette.sky, grid: true) {
                dictionaryButton
                wordDictionaryButton
                expressionDictionaryButton
                if examType == .kanken { yojiDictionaryButton }
            }
            launcherSection(L.sectionCollection[appLanguage], Palette.teal, grid: true) {
                statsButton
                wordbookButton
            }
        }
    }

    /// A titled group of launchers — one header plus its tiles, stacked on iPhone
    /// and two-up on iPad. Grouping by purpose (학습 / 사전 / 보관함) keeps the eight
    /// entries scannable instead of one long undifferentiated list.
    @ViewBuilder
    private func launcherSection<C: View>(
        _ title: String, _ accent: Color, grid: Bool = false,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title, accent: accent)
            if grid {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) { content() }
            } else {
                VStack(spacing: 12) { content() }
            }
        }
    }

    // MARK: Plan

    /// A slim home entry that opens the plan editor sheet.
    private var planButton: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { showPlan = true } } label: {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.sky)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.studyPlan[appLanguage])
                        .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                    Text("\(targetLevel) · \(L.perDayRate(newPerDay, appLanguage)) · ~\(daysToFinish(remaining: remaining, perDay: newPerDay))\(L.daysUnit[appLanguage])")
                        .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.inkSoft)
            }
            .cardBackground()
        }
        .buttonStyle(.bouncy)
    }

    /// The full plan editor, shown in the plan sheet. Both fields are live-linked:
    /// change the daily count and the goal date follows; change the goal date and
    /// the daily count follows. Pick whichever is easier to think about.
    /// A pill for one exam level, filled when it's the target.
    private func levelChip(_ level: String) -> some View {
        let selected = targetLevel == level
        return Button { targetLevel = level } label: {
            Text(level)
                .font(.kawaii(14, weight: .bold)).monospacedDigit()
                .foregroundStyle(selected ? .white : Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(selected ? Palette.accent : Palette.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Palette.ink.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.bouncy)
    }

    private var planEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(L.studyPlan[appLanguage], accent: Palette.sky)
            VStack(alignment: .leading, spacing: 8) {
                Text(L.examType[appLanguage])
                    .font(.kawaii(14, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                Picker(L.examType[appLanguage], selection: $examType) {
                    Text("JLPT").tag(ExamType.jlpt)
                    Text("漢検").tag(ExamType.kanken)
                }
                .pickerStyle(.segmented)
            }
            // Level chips wrap to as many rows as needed — a segmented control is
            // too cramped for 漢検's 10 levels on iPhone.
            VStack(alignment: .leading, spacing: 8) {
                Text(L.targetLevel[appLanguage])
                    .font(.kawaii(14, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach(examType.levels, id: \.self) { level in
                        levelChip(level)
                    }
                }
            }

            // How many kanji this 급수 has — shown prominently so the learner sees
            // the level's size at a glance while planning.
            HStack(spacing: 12) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Palette.sky).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(L.thisLevelKanji[appLanguage])
                    .font(.kawaii(15, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(levelTotal)")
                        .font(.kawaii(30, weight: .bold)).monospacedDigit().foregroundStyle(Palette.sky)
                        .contentTransition(.numericText()).animation(.snappy, value: levelTotal)
                    Text(L.unitCount[appLanguage])
                        .font(.kawaii(16, weight: .bold)).foregroundStyle(Palette.sky)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.skySoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // 시작 위치 — where in the level to begin (skip kanji already known),
            // so a returning learner can start mid-level instead of from the top.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.writeStartPos[appLanguage])
                        .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text(L.startFrom(studyStartIndex + 1, appLanguage))
                        .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.lavender)
                }
                Slider(value: Binding(
                    get: { Double(studyStartIndex) },
                    set: { studyStartIndex = min(Int($0), max(0, levelTotal - 1)) }),
                       in: 0...Double(max(1, levelTotal - 1)))
                    .tint(Palette.accent)
            }
            Divider()

            // 하루 몇 자 — the daily count (drives the goal date).
            Stepper(value: $newPerDay, in: 1...50) {
                HStack {
                    Text(L.perDayGoal[appLanguage])
                        .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text("\(newPerDay)\(L.perDayUnit[appLanguage])")
                        .font(.kawaii(22, weight: .bold)).foregroundStyle(Palette.pink)
                }
            }
            Divider()
            // 목표일 — the goal date (drives the daily count).
            DatePicker(L.planEnd[appLanguage], selection: goalDateBinding,
                       in: Date()..., displayedComponents: .date)
                .font(.kawaii(15))
            // A one-line plain-language summary of the resulting plan.
            Text("\(remaining)\(L.unitCount[appLanguage]) · \(L.perDayRate(newPerDay, appLanguage)) · ~\(goalDays)\(L.daysUnit[appLanguage])")
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
        }
        .cardBackground()
    }

    // MARK: Study-mode launchers

    /// The 학습 시작 launcher (also used inside the iPad grid). The badge is today's
    /// remaining new-kanji quota (hidden once the daily goal is met).
    private var studyLauncher: some View {
        launcher(icon: "pencil.and.outline", title: L.startStudy[appLanguage],
                 subtitle: L.newKanjiSub[appLanguage],
                 count: session.newIDs.isEmpty ? nil : session.newIDs.count,
                 soft: Palette.pinkSoft, accent: Palette.pink) { startStudyTapped() }
    }

    /// 오늘의 복습 — the spaced-repetition quiz over what was studied plus the
    /// questions whose review is due. It was built but had no way in.
    private var reviewLauncher: some View {
        launcher(icon: "arrow.triangle.2.circlepath", title: L.reviewQuiz[appLanguage],
                 subtitle: L.reviewQuizSub[appLanguage],
                 count: session.dueIDs.isEmpty ? nil : session.dueIDs.count,
                 soft: Palette.mintSoft, accent: Palette.mint) {
            store.send(.startQuiz(level: targetLevel, planned: session.newIDs))
        }
    }

    /// 오답 복습 — shown only while notebook entries are due.
    private var wrongNoteLauncher: some View {
        launcher(icon: "exclamationmark.bubble.fill", title: L.reviewWrongNotes[appLanguage],
                 subtitle: L.reviewWrongNotesSub[appLanguage], count: store.wrongDue,
                 soft: Palette.pinkSoft, accent: Palette.pinkDeep) {
            store.send(.startWrongNoteReview(level: targetLevel, language: appLanguage))
        }
    }

    private var dictionaryButton: some View {
        launcher(icon: "character.book.closed", title: L.kanjiDictionary[appLanguage],
                 subtitle: L.searchPrompt[appLanguage], count: nil,
                 soft: Palette.skySoft, accent: Palette.sky) { store.send(.openDictionary) }
    }

    /// The exam-question hub launcher — real-exam-shaped practice by section,
    /// titled for the active exam (JLPT 문제 / 칸켄 문제).
    private var kankenButton: some View {
        let title = examType == .kanken ? L.kankenHub[appLanguage] : L.jlptHub[appLanguage]
        return launcher(icon: "checklist", title: title,
                        subtitle: L.kankenHubSubtitle[appLanguage], count: nil,
                        soft: Palette.lavenderSoft, accent: Palette.lavender) {
            store.send(.startKanken(level: targetLevel))
        }
    }

    /// 사자성어 사전 — 四字熟語 browse. 漢검 전용 (JLPT엔 사자성어 유형이 없음).
    private var yojiDictionaryButton: some View {
        launcher(icon: "quote.bubble", title: L.yojiDictionary[appLanguage],
                 subtitle: L.kankenYojiDesc[appLanguage], count: nil,
                 soft: Palette.grapeSoft, accent: Palette.grape) {
            store.send(.openYojiDictionary)
        }
    }

    private var wordDictionaryButton: some View {
        // Every launcher gets its own hue so no two tiles clash (pink · lavender ·
        // sky · mint · teal · coral · butter · grape across the full set).
        launcher(icon: "text.book.closed", title: L.wordDictionary[appLanguage],
                 subtitle: L.wordSearchPrompt[appLanguage], count: nil,
                 soft: Palette.mintSoft, accent: Palette.mint) { store.send(.openWordDictionary) }
    }

    /// Celebration banner shown when every kanji in the current level is learned:
    /// advance to the next 급수, or a "all done" note at the last level.
    private var levelCompleteCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38)).foregroundStyle(Palette.mint)
            Text(L.levelCompleteTitle[appLanguage].replacingOccurrences(of: "{level}", with: targetLevel))
                .font(.kawaii(19, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
            if let next = nextLevel {
                Button { advanceLevel() } label: {
                    HStack(spacing: 6) {
                        Text(L.goToNextLevel[appLanguage].replacingOccurrences(of: "{level}", with: next))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    }
                    .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Palette.accent).clipShape(Capsule())
                }
                .buttonStyle(.bouncy)
            } else {
                Text(L.allLevelsComplete[appLanguage])
                    .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 16)
        .background(Palette.mintSoft)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Palette.mint.opacity(0.45), lineWidth: 1.5))
    }

    /// 쓰기 테스트 — free handwriting practice. Available on every device (iPhone
    /// included), not just iPad.
    private var practiceButton: some View {
        launcher(icon: "paintbrush.pointed.fill", title: L.startPractice[appLanguage],
                 subtitle: L.practiceSub[appLanguage], count: nil,
                 soft: Palette.butterSoft, accent: Palette.butter) {
            store.send(.startPractice(mode: .kanji))
        }
    }

    /// 즐겨찾기 — the writing test over the items starred while checking answers,
    /// in whichever mode was last used. Its own tile rather than a setting inside
    /// the test, because "test me on what I keep getting wrong" is the reason you
    /// open the app, not a variation you configure once you are already there.
    private var favoritesButton: some View {
        launcher(icon: "star.fill", title: L.favorites[appLanguage],
                 subtitle: L.writeFavoriteSub[appLanguage], count: nil,
                 soft: Palette.butterSoft, accent: Palette.butter) {
            store.send(.startPractice(mode: .kanji, favorites: true))
        }
    }

    /// 표현사전 — 慣用句・phrases split out of the word dictionary.
    private var expressionDictionaryButton: some View {
        launcher(icon: "quote.opening", title: L.expressionDictionary[appLanguage],
                 subtitle: L.expressionSub[appLanguage], count: nil,
                 soft: Palette.coralSoft, accent: Palette.coral) { store.send(.openExpressionDictionary) }
    }

    /// 학습 기록 — daily activity, per-level progress, exam readiness.
    private var statsButton: some View {
        launcher(icon: "chart.bar.xaxis", title: L.studyStats[appLanguage],
                 subtitle: L.studyStatsSub[appLanguage], count: nil,
                 soft: Palette.skySoft, accent: Palette.sky) {
            store.send(.openStats(level: targetLevel))
        }
    }

    /// The 단어장 (saved collection) — opens the bulk-manage overlay for the
    /// bookmarked kanji + saved words. Count badge = total saved items.
    private var wordbookButton: some View {
        let total = bookmarkedKanji.count + store.wordReview.words.count
        return launcher(icon: "bookmark.fill", title: L.wordbook[appLanguage],
                        subtitle: "\(L.kanji[appLanguage]) \(bookmarkedKanji.count) · \(L.words[appLanguage]) \(store.wordReview.words.count)",
                        count: total > 0 ? total : nil,
                        soft: Palette.tealSoft, accent: Palette.teal) {
            store.send(.setShowWordbook(true))
        }
    }

    private func launcher(
        icon: String, title: String, subtitle: String, count: Int?,
        soft: Color, accent: Color, dimmed: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 56, height: 56)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.kawaii(19, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle).font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                if let count {
                    Text("\(count)").font(.kawaii(24, weight: .bold)).monospacedDigit()
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: count)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(accent)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [soft, soft.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1.5))
            .opacity(dimmed ? 0.55 : 1)
        }
        .buttonStyle(.bouncy)
    }

    // MARK: 단어장 (bulk manage saved kanji + words)

    private func closeWordbook() { store.send(.setShowWordbook(false)) }

    /// The 단어장 as a full-screen overlay (same presentation as plan/settings):
    /// saved kanji and words, each openable and removable in one place.
    private var wordbookOverlay: some View {
        let isEmpty = bookmarkedKanji.isEmpty && store.wordReview.words.isEmpty
        return Group {
            if isEmpty {
                ScrollView { emptyWordbook.padding(20).readableWidth(sizeClass) }
            } else {
                wordbookList
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 12) {
                OverlayHeader(title: L.wordbook[appLanguage]) { closeWordbook() }
                if !isEmpty {
                    Picker("", selection: $wordbookTab) {
                        Text("\(L.kanji[appLanguage]) \(bookmarkedKanji.count)").tag(0)
                        Text("\(L.words[appLanguage]) \(store.wordReview.words.count)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20).readableWidth(sizeClass)
                    HStack(spacing: 10) {
                        cardStudyButton
                        if wordbookTab == 1, !store.wordReview.dueIDs.isEmpty {
                            wordReviewButton
                        }
                    }
                    .padding(.horizontal, 20).readableWidth(sizeClass)
                }
            }
            .padding(.bottom, 6)
            .background(Palette.background)
        }
        .background(Palette.background.ignoresSafeArea())
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    /// The active tab's saved items in a List, so rows swipe to delete (no inline
    /// delete icons). Kanji rows reuse the dictionary's KanjiListRow for a look
    /// consistent with 한자사전; words match 단어사전.
    @ViewBuilder private var wordbookList: some View {
        List {
            if wordbookTab == 0 {
                ForEach(Array(bookmarkedKanji.enumerated()), id: \.element.id) { i, kanji in
                    KanjiListRow(kanji: kanji,
                                 meaning: kanjiGloss(store.review.glosses[kanji.id] ?? [:], appLanguage),
                                 tint: Palette.tint(i), language: appLanguage) {
                        closeWordbook(); store.send(.kanjiSelected(kanji))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.send(.removeBookmarkedKanji(kanji.id)) } label: {
                            Label(L.delete[appLanguage], systemImage: "trash")
                        }
                    }
                }
            } else {
                ForEach(store.wordReview.words.elements) { word in
                    wordbookWordRow(word)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.send(.wordReview(.remove(wordID: word.id))) } label: {
                                Label(L.delete[appLanguage], systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .padding(.horizontal, 16)
        .readableWidth(sizeClass)
    }

    private func wordbookWordRow(_ word: WordEntry) -> some View {
        Button {
            closeWordbook(); store.send(.wordReview(.wordTapped(word)))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    RubyWord(word.surface, reading: word.reading, size: 20)
                    if let meaning = wordMeaningText(word, appLanguage), !meaning.isEmpty {
                        Text(meaning).font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }

    /// Starts a flashcard session over the current tab's saved items.
    private var cardStudyButton: some View {
        Button {
            flashcards = wordbookTab == 0 ? kanjiFlashcards : wordFlashcards
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 13, weight: .bold))
                Text(L.flashcards[appLanguage]).font(.kawaii(14, weight: .bold, language: appLanguage))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Palette.accent).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
        .disabled(wordbookTab == 0 ? bookmarkedKanji.isEmpty : store.wordReview.words.isEmpty)
    }

    /// 복습 N — the saved words that are due, graded with the four FSRS buttons.
    private var wordReviewButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showWordReview = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .bold))
                Text("\(L.review[appLanguage]) \(store.wordReview.dueIDs.count)")
                    .font(.kawaii(14, weight: .bold, language: appLanguage))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Palette.mintDeep).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }

    private var wordReviewOverlay: some View {
        WordReviewHubView(wordStore: store.scope(state: \.wordReview, action: \.wordReview))
            .safeAreaInset(edge: .top) {
                OverlayHeader(title: L.review[appLanguage]) {
                    withAnimation(.easeOut(duration: 0.18)) { showWordReview = false }
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    private var kanjiFlashcards: [FlashcardItem] {
        bookmarkedKanji.map { kanji in
            let on = kanji.onReadings.isEmpty ? nil : "\(L.onReading[appLanguage]) \(kanji.onReadings.prefix(4).joined(separator: "、"))"
            let kun = kanji.kunReadings.isEmpty ? nil : "\(L.kunReading[appLanguage]) \(kanji.kunReadings.prefix(4).joined(separator: "、"))"
            return FlashcardItem(
                id: kanji.id, front: kanji.literal, frontReading: nil,
                back: kanjiGloss(store.review.glosses[kanji.id] ?? [:], appLanguage) ?? "",
                backSub: [on, kun].compactMap { $0 }.joined(separator: "\n"), isKanji: true)
        }
    }

    private var wordFlashcards: [FlashcardItem] {
        store.wordReview.words.elements.map { word in
            FlashcardItem(
                id: word.id, front: word.surface, frontReading: word.reading,
                back: wordMeaningText(word, appLanguage) ?? "", backSub: "", isKanji: false)
        }
    }

    private var emptyWordbook: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 40, weight: .light)).foregroundStyle(Palette.inkSoft)
            Text(L.wordbookEmpty[appLanguage])
                .font(.kawaii(16, weight: .semibold, language: appLanguage)).foregroundStyle(Palette.ink)
            Text(L.wordbookEmptyHint[appLanguage])
                .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

private extension View {
    /// The shared soft-card container used by Home sections.
    func cardBackground() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Palette.ink.opacity(0.05), radius: 8, y: 3)
    }
}

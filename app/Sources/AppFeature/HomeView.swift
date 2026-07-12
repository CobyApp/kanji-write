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
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPlan = false

    private var levelOrder: [Kanji] { studyOrder(store.review.kanji.elements, level: targetLevel) }
    private var learnedInLevel: Int {
        let tracked = Set(store.review.records.ids)
        return levelOrder.filter { tracked.contains($0.id) }.count
    }
    private var levelTotal: Int { max(levelOrder.count, 1) }
    private var progress: Double { Double(learnedInLevel) / Double(levelTotal) }
    private var session: StudySession {
        todaysSession(records: store.review.records.elements, order: levelOrder,
                      today: store.review.today, newPerDay: newPerDay)
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
    private var goalFraction: Double { newPerDay > 0 ? min(Double(doneToday) / Double(newPerDay), 1) : 0 }
    private var remaining: Int { remainingNew(order: levelOrder, records: store.review.records.elements) }

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
            level: targetLevel, dailyGoal: newPerDay, doneToday: doneToday, streak: streak,
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
                    if sizeClass == .compact { compactLayout } else { padPortraitLayout }
                }
                .padding(.horizontal, sizeClass == .compact ? 22 : 34)
                .padding(.top, 22)
                .padding(.bottom, 56)
                .readableWidth(sizeClass)
            }
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            store.send(.bookmarksAppeared)
            store.send(.wordReview(.onAppear))
            writeSnapshot()
        }
        .onChange(of: newPerDay) { _, _ in writeSnapshot() }
        .onChange(of: targetLevel) { _, _ in writeSnapshot() }
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
        .transition(.opacity)
    }

    // MARK: Greeting + ring

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.greeting[appLanguage])
                .font(.kawaii(24, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
            Text("\(targetLevel) · \(learnedInLevel)/\(levelTotal)")
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
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
        VStack(spacing: 22) {
            greeting.popIn(delay: 0.02)
            ring(168).popIn(delay: 0.08)
            HStack(spacing: 14) { streakChip; goalChip }.popIn(delay: 0.12)
            planButton.popIn(delay: 0.16)
            launchers.popIn(delay: 0.22)
            dictionaryButton.popIn(delay: 0.28)
            // iPhone is a single narrow column — each launcher gets its own full
            // row (side-by-side cards would be cramped).
            wordDictionaryButton.popIn(delay: 0.32)
            wordbookButton.popIn(delay: 0.38)
        }
    }

    /// iPad portrait: a centered column — ring + stats on top, plan below full
    /// width, launchers in a 2-up grid. (Taller than it is wide, so no side panes.)
    @ViewBuilder private var padPortraitLayout: some View {
        VStack(spacing: 28) {
            greeting.popIn(delay: 0.02)
            ring(200).popIn(delay: 0.08)
            HStack(spacing: 16) { streakChip; goalChip }.popIn(delay: 0.12)
            planButton.popIn(delay: 0.16)
            launchersGrid.popIn(delay: 0.22)
        }
    }

    // MARK: Streak + today's goal chips

    private var streakChip: some View {
        VStack(spacing: 4) {
            Text("\(streak)").font(.kawaii(26, weight: .bold)).foregroundStyle(Palette.butter)
                .contentTransition(.numericText()).animation(.snappy, value: streak)
            Text(L.streak[appLanguage]).font(.kawaii(12)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(Palette.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 5, y: 2)
    }

    private var goalChip: some View {
        VStack(spacing: 6) {
            Text("\(doneToday)/\(newPerDay)")
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
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Palette.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 5, y: 2)
    }

    /// The four launchers as a 2-column grid (iPad).
    private var launchersGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                  spacing: 14) {
            launcher(icon: "pencil.and.outline", title: L.startStudy[appLanguage],
                     subtitle: L.newKanjiSub[appLanguage], count: session.newIDs.count,
                     soft: Palette.pinkSoft, accent: Palette.pink) { store.send(.startStudy) }
            quizLauncher
            // Free handwriting is an Apple-Pencil activity → iPad only.
            if Platform.isPad {
                launcher(icon: "paintbrush.pointed.fill", title: L.startPractice[appLanguage],
                         subtitle: L.practiceSub[appLanguage], count: nil,
                         soft: Palette.mintSoft, accent: Palette.mint) { store.send(.startPractice) }
            }
            dictionaryButton
            wordDictionaryButton
            wordbookButton
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
                    Text("\(targetLevel) · \(newPerDay)\(L.perDayUnit[appLanguage]) · ~\(daysToFinish(remaining: remaining, perDay: newPerDay))\(L.daysUnit[appLanguage])")
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
    private var planEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(L.studyPlan[appLanguage], accent: Palette.sky)
            Picker(L.targetLevel[appLanguage], selection: $targetLevel) {
                ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

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
            Text("\(remaining)\(L.perDayUnit[appLanguage]) · \(newPerDay)\(L.perDayUnit[appLanguage])/\(L.daysUnit[appLanguage]) · ~\(goalDays)\(L.daysUnit[appLanguage])")
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
        }
        .cardBackground()
    }

    // MARK: Study-mode launchers

    /// Compact (iPhone) launchers — learn + quiz (which folds in review). Practice
    /// (free writing) is an iPad/Apple-Pencil activity, so it's omitted here.
    private var launchers: some View {
        VStack(spacing: 14) {
            launcher(icon: "pencil.and.outline", title: L.startStudy[appLanguage],
                     subtitle: L.newKanjiSub[appLanguage], count: session.newIDs.count,
                     soft: Palette.pinkSoft, accent: Palette.pink) { store.send(.startStudy) }
            quizLauncher
        }
    }

    /// The quiz — one place that mixes review (spaced-repetition due items) with
    /// new questions on what was studied today. Badge shows kanji due for review.
    private var quizLauncher: some View {
        let due = session.dueIDs.count
        return launcher(icon: "questionmark.circle.fill", title: L.quiz[appLanguage],
                        subtitle: due > 0 ? L.reviewSub[appLanguage] : L.quizSub[appLanguage],
                        count: due > 0 ? due : nil,
                        soft: Palette.lavenderSoft, accent: Palette.lavender) {
            // Pass today's planned new kanji so the quiz works even before study.
            store.send(.startQuiz(level: targetLevel, planned: session.newIDs))
        }
    }

    private var dictionaryButton: some View {
        launcher(icon: "character.book.closed", title: L.kanjiDictionary[appLanguage],
                 subtitle: L.searchPrompt[appLanguage], count: nil,
                 soft: Palette.skySoft, accent: Palette.sky) { store.send(.openDictionary) }
    }

    private var wordDictionaryButton: some View {
        // Butter so each launcher owns a distinct hue (pink · lavender · mint ·
        // sky · butter) — no two tiles share a color.
        launcher(icon: "text.book.closed", title: L.wordDictionary[appLanguage],
                 subtitle: L.wordSearchPrompt[appLanguage], count: nil,
                 soft: Palette.butterSoft, accent: Palette.butter) { store.send(.openWordDictionary) }
    }

    /// The 단어장 (saved collection) — opens the bulk-manage overlay for the
    /// bookmarked kanji + saved words. Count badge = total saved items.
    private var wordbookButton: some View {
        let total = bookmarkedKanji.count + store.wordReview.words.count
        return launcher(icon: "bookmark.fill", title: L.wordbook[appLanguage],
                        subtitle: "\(L.kanji[appLanguage]) \(bookmarkedKanji.count) · \(L.words[appLanguage]) \(store.wordReview.words.count)",
                        count: total > 0 ? total : nil,
                        soft: Palette.coralSoft, accent: Palette.coral) {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if bookmarkedKanji.isEmpty && store.wordReview.words.isEmpty {
                    emptyWordbook
                } else {
                    if !bookmarkedKanji.isEmpty { savedKanjiSection }
                    if !store.wordReview.words.isEmpty { savedWordsSection }
                }
            }
            .padding(20)
            .readableWidth(sizeClass)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) {
            OverlayHeader(title: L.wordbook[appLanguage]) { closeWordbook() }
        }
        .background(Palette.background.ignoresSafeArea())
        .transition(.opacity)
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

    private var savedKanjiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.kanji[appLanguage], accent: Palette.pink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                ForEach(Array(bookmarkedKanji.enumerated()), id: \.element.id) { i, kanji in
                    let tint = Palette.tint(i)
                    Button {
                        closeWordbook()
                        store.send(.kanjiSelected(kanji))
                    } label: {
                        PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                   size: 60, fontSize: 32)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        removeBadge { store.send(.removeBookmarkedKanji(kanji.id)) }
                    }
                }
            }
        }
        .cardBackground()
    }

    private var savedWordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.words[appLanguage], accent: Palette.lavender)
            ForEach(store.wordReview.words.elements) { word in
                HStack(spacing: 8) {
                    Button {
                        closeWordbook()
                        store.send(.wordReview(.wordTapped(word)))
                    } label: {
                        HStack {
                            Text("\(word.surface)（\(word.reading)）")
                                .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { store.send(.wordReview(.remove(wordID: word.id))) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.pink)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .cardBackground()
    }

    /// A small ✕ badge overlaid on a saved tile to remove it.
    private func removeBadge(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white, Palette.pink)
                .background(Circle().fill(.white).padding(3))
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
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

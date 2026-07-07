import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI

/// The single Home dashboard — every feature on one scrolling screen: progress
/// ring, study plan (level + date range → daily goal), the three study-mode
/// launchers (learn / review / practice), a dictionary entry, and a bookmarks
/// preview. Details push; sessions cover; settings is a sheet (toolbar gear).
struct HomeView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    @AppStorage("planStartTS") private var planStartTS: Double = 0
    @AppStorage("planEndTS") private var planEndTS: Double = 0
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

    // Plan: level + start/goal dates → daily goal.
    private var startDate: Date {
        planStartTS > 0 ? Date(timeIntervalSince1970: planStartTS) : Date()
    }
    private var endDate: Date {
        planEndTS > 0 ? Date(timeIntervalSince1970: planEndTS) : Date().addingTimeInterval(60 * 86_400)
    }
    /// Days left from *today* to the goal date (≥1). Using the remaining time —
    /// not the original start→end span — makes the daily target adaptive: it
    /// rises as the deadline nears or if you fall behind, and the estimate stays
    /// honest. Clamped to 1 once the goal date has passed (finish today).
    private var daysLeft: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let goal = cal.startOfDay(for: endDate)
        return max(1, cal.dateComponents([.day], from: today, to: goal).day ?? 1)
    }
    /// New kanji/day needed to finish the level's remaining kanji by the goal date.
    private var plannedPerDay: Int {
        max(1, Int((Double(max(1, levelTotal - learnedInLevel)) / Double(daysLeft)).rounded(.up)))
    }
    private func syncPerDay() { newPerDay = min(50, plannedPerDay) }

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

    var body: some View {
        ZStack {
            AuroraBackground()
            FloatingBlobs()
            ScrollView {
                Group {
                    if sizeClass == .compact { compactLayout } else { padPortraitLayout }
                }
                .padding(.horizontal, sizeClass == .compact ? 18 : 26)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: sizeClass == .compact ? 560 : 900)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.send(.setShowSettings(true)) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(L.settings[appLanguage])
            }
        }
        .onChange(of: targetLevel) { _, _ in syncPerDay() }
        .onChange(of: planStartTS) { _, _ in syncPerDay() }
        .onChange(of: planEndTS) { _, _ in syncPerDay() }
        .task {
            syncPerDay()  // keep the active per-day (goal chip / session) equal to the plan
            store.send(.bookmarksAppeared)
            store.send(.wordReview(.onAppear))
        }
        .sheet(isPresented: $showPlan) {
            NavigationStack {
                ScrollView { planEditor.padding(20) }
                    .background(Palette.background)
                    .navigationTitle(L.studyPlan[appLanguage])
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L.close[appLanguage]) { showPlan = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .tint(Palette.accent)
            .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        }
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
        VStack(spacing: 16) {
            greeting.popIn(delay: 0.02)
            ring(168).popIn(delay: 0.08)
            HStack(spacing: 12) { streakChip; goalChip }.popIn(delay: 0.12)
            planButton.popIn(delay: 0.16)
            launchers.popIn(delay: 0.22)
            dictionaryButton.popIn(delay: 0.28)
            bookmarksSection.popIn(delay: 0.34)
        }
    }

    /// iPad portrait: a centered column — ring + stats on top, plan below full
    /// width, launchers in a 2-up grid. (Taller than it is wide, so no side panes.)
    @ViewBuilder private var padPortraitLayout: some View {
        VStack(spacing: 20) {
            greeting.popIn(delay: 0.02)
            ring(200).popIn(delay: 0.08)
            HStack(spacing: 14) { streakChip; goalChip }.popIn(delay: 0.12)
            planButton.popIn(delay: 0.16)
            launchersGrid.popIn(delay: 0.22)
            bookmarksSection.popIn(delay: 0.30)
        }
    }

    // MARK: Streak + today's goal chips

    private var streakChip: some View {
        VStack(spacing: 4) {
            Text("\(streak)").font(.kawaii(26, weight: .bold)).foregroundStyle(Palette.butter)
                .contentTransition(.numericText()).animation(.snappy, value: streak)
            Text(L.streak[appLanguage]).font(.kawaii(12)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
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
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Palette.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 5, y: 2)
    }

    /// The four launchers as a 2-column grid (iPad).
    private var launchersGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            launcher(icon: "pencil.and.outline", title: L.startStudy[appLanguage],
                     subtitle: L.newKanjiSub[appLanguage], count: session.newIDs.count,
                     soft: Palette.pinkSoft, accent: Palette.pink) { store.send(.startStudy) }
            quizLauncher
            launcher(icon: "paintbrush.pointed.fill", title: L.startPractice[appLanguage],
                     subtitle: L.practiceSub[appLanguage], count: nil,
                     soft: Palette.mintSoft, accent: Palette.mint) { store.send(.startPractice) }
            dictionaryButton
        }
    }

    // MARK: Plan

    /// A slim home entry that opens the plan editor sheet.
    private var planButton: some View {
        Button { showPlan = true } label: {
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

    /// The full plan editor, shown inside the plan sheet.
    private var planEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L.studyPlan[appLanguage], accent: Palette.sky)
            Picker(L.targetLevel[appLanguage], selection: $targetLevel) {
                ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker(L.planStart[appLanguage], selection: Binding(
                get: { startDate }, set: { planStartTS = $0.timeIntervalSince1970 }),
                displayedComponents: .date)
                .font(.kawaii(15))
            DatePicker(L.planEnd[appLanguage], selection: Binding(
                get: { endDate }, set: { planEndTS = $0.timeIntervalSince1970 }),
                in: startDate..., displayedComponents: .date)
                .font(.kawaii(15))
            HStack {
                Text(L.perDayGoal[appLanguage])
                    .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                Spacer()
                Text("\(newPerDay)\(L.perDayUnit[appLanguage])")
                    .font(.kawaii(22, weight: .bold)).foregroundStyle(Palette.pink)
            }
        }
        .cardBackground()
    }

    // MARK: Study-mode launchers

    /// Compact (iPhone) launchers — learn + quiz (which folds in review). Practice
    /// (free writing) is an iPad/Apple-Pencil activity, so it's omitted here.
    private var launchers: some View {
        VStack(spacing: 12) {
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
            store.send(.startQuiz(level: targetLevel))
        }
    }

    private var dictionaryButton: some View {
        launcher(icon: "character.book.closed", title: L.dictionary[appLanguage],
                 subtitle: L.searchPrompt[appLanguage], count: nil,
                 soft: Palette.skySoft, accent: Palette.sky) { store.send(.openDictionary) }
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
            .padding(16)
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

    // MARK: Bookmarks preview

    @ViewBuilder private var bookmarksSection: some View {
        if !bookmarkedKanji.isEmpty || !store.wordReview.words.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L.bookmarks[appLanguage], accent: Palette.butter)
                if !bookmarkedKanji.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(bookmarkedKanji.enumerated()), id: \.element.id) { i, kanji in
                                let tint = Palette.tint(i)
                                Button { store.send(.kanjiSelected(kanji)) } label: {
                                    PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                               size: 52, fontSize: 28)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ForEach(store.wordReview.words.elements) { word in
                    Button { store.send(.wordReview(.wordTapped(word))) } label: {
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
                }
            }
            .cardBackground()
        }
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

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
    private var planDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
    }
    private var plannedPerDay: Int {
        max(1, Int((Double(max(1, levelTotal - learnedInLevel)) / Double(planDays)).rounded(.up)))
    }
    private func syncPerDay() { newPerDay = min(50, plannedPerDay) }

    private var bookmarkedKanji: [Kanji] {
        let ids = Set(store.bookmarkedIDs)
        return store.review.kanji.elements.filter { ids.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            FloatingBlobs()
            ScrollView {
                VStack(spacing: 22) {
                    greeting.popIn(delay: 0.02)
                    ring.popIn(delay: 0.08)
                    planCard.popIn(delay: 0.14)
                    launchers.popIn(delay: 0.20)
                    dictionaryButton.popIn(delay: 0.26)
                    bookmarksSection.popIn(delay: 0.32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.today[appLanguage])
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
            store.send(.bookmarksAppeared)
            store.send(.wordReview(.onAppear))
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

    private var ring: some View {
        ProgressRing(progress: progress, size: 172, lineWidth: 18) {
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.kawaii(38, weight: .bold)).foregroundStyle(Palette.ink)
                Text(targetLevel).font(.kawaii(15, weight: .bold)).foregroundStyle(Palette.pink)
            }
        }
    }

    // MARK: Plan

    private var planCard: some View {
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
                Text("\(plannedPerDay)\(L.perDayUnit[appLanguage])")
                    .font(.kawaii(22, weight: .bold)).foregroundStyle(Palette.pink)
            }
        }
        .cardBackground()
    }

    // MARK: Study-mode launchers

    private var launchers: some View {
        VStack(spacing: 12) {
            launcher(icon: "pencil.and.outline", title: L.startStudy[appLanguage],
                     subtitle: L.newKanjiSub[appLanguage], count: session.newIDs.count,
                     soft: Palette.pinkSoft, accent: Palette.pink) { store.send(.startStudy) }
            let due = session.dueIDs.count
            launcher(icon: "arrow.2.circlepath", title: L.review[appLanguage],
                     subtitle: due > 0 ? L.reviewSub[appLanguage] : L.allCaughtUp[appLanguage],
                     count: due, soft: Palette.lavenderSoft, accent: Palette.lavender,
                     dimmed: due == 0) { if due > 0 { store.send(.startReview) } }
            launcher(icon: "paintbrush.pointed.fill", title: L.startPractice[appLanguage],
                     subtitle: L.practiceSub[appLanguage], count: nil,
                     soft: Palette.mintSoft, accent: Palette.mint) { store.send(.startPractice) }
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
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(soft)
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

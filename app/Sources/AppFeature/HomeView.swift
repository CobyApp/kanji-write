import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI

/// The 오늘/Home dashboard: a glanceable greeting, an animated level-progress
/// ring, a one-tap "keep going" launcher, and small stat chips. The full study
/// menu lives in the 학습 hub.
struct HomeView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    @AppStorage("planStartTS") private var planStartTS: Double = 0
    @AppStorage("planEndTS") private var planEndTS: Double = 0

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

    // MARK: Plan (level + date range → per-day goal)

    private var startDate: Date {
        planStartTS > 0 ? Date(timeIntervalSince1970: planStartTS) : Date()
    }
    private var endDate: Date {
        planEndTS > 0 ? Date(timeIntervalSince1970: planEndTS) : Date().addingTimeInterval(60 * 86_400)
    }
    private var planDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
    }
    /// Kanji/day needed to finish the level's remaining kanji by the goal date.
    private var plannedPerDay: Int {
        let remaining = max(1, levelTotal - learnedInLevel)
        return max(1, Int((Double(remaining) / Double(planDays)).rounded(.up)))
    }

    private func syncPerDay() { newPerDay = min(50, plannedPerDay) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            FloatingBlobs()
            ScrollView {
                VStack(spacing: 28) {
                    greeting.popIn(delay: 0.02)
                    ring.popIn(delay: 0.08)
                    planCard.popIn(delay: 0.14)
                    continueButton.popIn(delay: 0.20)
                    statsRow.popIn(delay: 0.28)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.today[appLanguage])
        .onChange(of: targetLevel) { _, _ in syncPerDay() }
        .onChange(of: planStartTS) { _, _ in syncPerDay() }
        .onChange(of: planEndTS) { _, _ in syncPerDay() }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(L.studyPlan[appLanguage], accent: Palette.sky)
            Picker(L.targetLevel[appLanguage], selection: $targetLevel) {
                ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker(
                L.planStart[appLanguage],
                selection: Binding(
                    get: { startDate },
                    set: { planStartTS = $0.timeIntervalSince1970 }),
                displayedComponents: .date)
                .font(.kawaii(15))
            DatePicker(
                L.planEnd[appLanguage],
                selection: Binding(
                    get: { endDate },
                    set: { planEndTS = $0.timeIntervalSince1970 }),
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 8, y: 3)
    }

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
        ProgressRing(progress: progress, size: 190, lineWidth: 20) {
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))%")
                    .font(.kawaii(40, weight: .bold)).foregroundStyle(Palette.ink)
                Text(targetLevel).font(.kawaii(15, weight: .bold)).foregroundStyle(Palette.pink)
            }
        }
        .padding(.vertical, 8)
    }

    private var continueButton: some View {
        Button { store.send(.startStudy) } label: {
            HStack(spacing: 14) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.continueStudy[appLanguage])
                        .font(.kawaii(20, weight: .bold, language: appLanguage))
                    Text(L.newKanjiSub[appLanguage])
                        .font(.kawaii(13)).opacity(0.9)
                }
                Spacer()
                Text("\(session.newIDs.count)")
                    .font(.kawaii(26, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.vertical, 22).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Palette.pink, Palette.accent, Palette.lavender],
                               startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Palette.pink.opacity(0.4), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.bouncy)
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            statChip(L.learned[appLanguage], store.review.records.count, Palette.mint)
            statChip(L.review[appLanguage], session.dueIDs.count, Palette.lavender)
            statChip(L.newItems[appLanguage], session.newIDs.count, Palette.butter)
        }
    }

    private func statChip(_ label: String, _ value: Int, _ accent: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)").font(.kawaii(28, weight: .bold)).foregroundStyle(accent)
            Text(label).font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Palette.card.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 6, y: 3)
    }
}

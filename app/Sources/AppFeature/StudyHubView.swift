import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import StudyPlan
import SwiftUI

/// The 学習 tab: study plan (today's new kanji) and SRS review (due cards) in one
/// daily hub. Composes the existing StudyPlan and Review stores.
public struct StudyHubView: View {
    @Bindable var planStore: StoreOf<StudyPlanFeature>
    @Bindable var reviewStore: StoreOf<ReviewFeature>
    @State private var selectedDays = 10

    public init(planStore: StoreOf<StudyPlanFeature>, reviewStore: StoreOf<ReviewFeature>) {
        self.planStore = planStore
        self.reviewStore = reviewStore
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if let plan = planStore.plan {
                        progressCard(plan)
                        todayCard(plan)
                    } else {
                        createCard
                    }
                    reviewCard
                }
                .padding(16)
            }
        }
        .navigationTitle("学習")
        .task {
            planStore.send(.onAppear)
            reviewStore.send(.onAppear)
        }
    }

    // MARK: Plan

    private var createCard: some View {
        VStack(spacing: 16) {
            SectionHeader("学習プラン", accent: Palette.pink)
            Picker("期間", selection: $selectedDays) {
                Text("10日").tag(10); Text("14日").tag(14); Text("30日").tag(30)
            }
            .pickerStyle(.segmented)
            Button { planStore.send(.createPlan(days: selectedDays)) } label: {
                Text("プラン作成").font(.kawaii(17, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Palette.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .roundedCard()
    }

    private func progressCard(_ plan: StudyPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("進捗", accent: Palette.mint)
            ProgressView(value: plan.progress).tint(Palette.mint)
            Text("\(plan.completedCount) / \(plan.totalCount)")
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    private func todayCard(_ plan: StudyPlan) -> some View {
        let dayIndex = plan.scheduledDayIndex(today: planStore.today) ?? plan.currentDayIndex
        let ids = plan.dayAssignments.indices.contains(dayIndex) ? plan.dayAssignments[dayIndex] : []
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("今日学ぶ (Day \(dayIndex + 1))", accent: Palette.butter)
            if ids.isEmpty {
                Text("今日の割り当てはありません").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
            }
            ForEach(ids, id: \.self) { id in
                if let kanji = planStore.kanji[id: id] {
                    HStack(spacing: 14) {
                        Button { planStore.send(.kanjiTapped(kanji)) } label: {
                            HStack(spacing: 14) {
                                PastelTile(kanji.literal, soft: Palette.butterSoft, accent: Palette.butter,
                                           size: 50, fontSize: 28)
                                Text(kanji.onReadings.joined(separator: "、"))
                                    .font(.kawaii(15)).foregroundStyle(Palette.ink)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button { planStore.send(.markDone(id)) } label: {
                            Image(systemName: plan.completedKanjiIDs.contains(id)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 25))
                                .foregroundStyle(plan.completedKanjiIDs.contains(id)
                                                 ? Palette.mint : Palette.inkSoft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .roundedCard()
    }

    // MARK: Review

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("復習", accent: Palette.lavender)
            if reviewStore.dueKanji.isEmpty {
                Text("今日の復習はありません").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
            }
            ForEach(reviewStore.dueKanji) { kanji in
                HStack(spacing: 12) {
                    Button { reviewStore.send(.kanjiTapped(kanji)) } label: {
                        PastelTile(kanji.literal, soft: Palette.lavenderSoft, accent: Palette.lavender,
                                   size: 50, fontSize: 28)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("もう一度") { reviewStore.send(.grade(kanjiID: kanji.id, correct: false)) }
                        .font(.kawaii(13, weight: .bold)).foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Palette.card).clipShape(Capsule())
                        .overlay(Capsule().stroke(Palette.inkSoft.opacity(0.3), lineWidth: 1))
                    Button("正解") { reviewStore.send(.grade(kanjiID: kanji.id, correct: true)) }
                        .font(.kawaii(13, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Palette.lavender).clipShape(Capsule())
                }
            }
        }
        .roundedCard()
    }
}

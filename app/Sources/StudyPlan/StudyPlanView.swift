import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct StudyPlanView: View {
    @Bindable public var store: StoreOf<StudyPlanFeature>
    @State private var selectedDays = 10

    public init(store: StoreOf<StudyPlanFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let plan = store.plan {
                planContent(plan)
            } else {
                createContent
            }
        }
        .navigationTitle("プラン")
        .task { store.send(.onAppear) }
    }

    private var createContent: some View {
        VStack(spacing: 20) {
            Text("学習プランを作成")
                .font(.kawaii(22, weight: .bold)).foregroundStyle(Palette.ink)
            Picker("期間", selection: $selectedDays) {
                Text("10日").tag(10)
                Text("14日").tag(14)
                Text("30日").tag(30)
            }
            .pickerStyle(.segmented)
            Button {
                store.send(.createPlan(days: selectedDays))
            } label: {
                Text("プラン作成")
                    .font(.kawaii(17, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Palette.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .roundedCard()
        .padding(16)
    }

    private func planContent(_ plan: StudyPlan) -> some View {
        let dayIndex = plan.scheduledDayIndex(today: store.today) ?? plan.currentDayIndex
        let todaysIDs = plan.dayAssignments.indices.contains(dayIndex)
            ? plan.dayAssignments[dayIndex] : []
        return ScrollView {
            VStack(spacing: 16) {
                progressCard(plan)
                todayCard(plan, dayIndex: dayIndex, todaysIDs: todaysIDs)
            }
            .padding(16)
        }
    }

    private func progressCard(_ plan: StudyPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("進捗", accent: Palette.mint)
            ProgressView(value: plan.progress)
                .tint(Palette.mint)
            Text("\(plan.completedCount) / \(plan.totalCount)")
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    private func todayCard(_ plan: StudyPlan, dayIndex: Int, todaysIDs: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("今日の漢字 (Day \(dayIndex + 1))", accent: Palette.butter)
            ForEach(Array(todaysIDs.enumerated()), id: \.element) { index, id in
                if let kanji = store.kanji[id: id] {
                    let tint = Palette.tint(index)
                    HStack(spacing: 14) {
                        Button {
                            store.send(.kanjiTapped(kanji))
                        } label: {
                            HStack(spacing: 14) {
                                PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                           size: 52, fontSize: 30)
                                Text(kanji.onReadings.joined(separator: "、"))
                                    .font(.kawaii(15)).foregroundStyle(Palette.ink)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            store.send(.markDone(id))
                        } label: {
                            Image(systemName: plan.completedKanjiIDs.contains(id)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 26))
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
}

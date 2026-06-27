import ComposableArchitecture
import SharedModels
import SwiftUI

public struct StudyPlanView: View {
    @Bindable public var store: StoreOf<StudyPlanFeature>
    @State private var selectedDays = 10

    public init(store: StoreOf<StudyPlanFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
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
        VStack(spacing: 24) {
            Text("学習プランを作成").font(.title2)
            Picker("期間", selection: $selectedDays) {
                Text("10日").tag(10)
                Text("14日").tag(14)
                Text("30日").tag(30)
            }
            .pickerStyle(.segmented)
            Button("プラン作成") { store.send(.createPlan(days: selectedDays)) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func planContent(_ plan: StudyPlan) -> some View {
        let dayIndex = plan.scheduledDayIndex(today: store.today) ?? plan.currentDayIndex
        let todaysIDs = plan.dayAssignments.indices.contains(dayIndex)
            ? plan.dayAssignments[dayIndex] : []
        return VStack(spacing: 0) {
            ProgressView(value: plan.progress) {
                Text("進捗 \(plan.completedCount) / \(plan.totalCount)")
            }
            .padding()
            List {
                Section("今日の漢字 (Day \(dayIndex + 1))") {
                    ForEach(todaysIDs, id: \.self) { id in
                        if let kanji = store.kanji[id: id] {
                            HStack {
                                Button {
                                    store.send(.kanjiTapped(kanji))
                                } label: {
                                    Text(kanji.literal).font(.title)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    store.send(.markDone(id))
                                } label: {
                                    Image(systemName: plan.completedKanjiIDs.contains(id)
                                          ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

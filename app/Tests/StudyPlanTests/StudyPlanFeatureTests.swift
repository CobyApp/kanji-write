import ComposableArchitecture
import SharedModels
import XCTest

@testable import StudyPlan

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
    static let gaku = Kanji(id: 2, literal: "学", strokeCount: 8, grade: 1,
                            jlptLevel: "N5", onReadings: ["ガク"], kunReadings: ["まな.ぶ"])
}

@MainActor
final class StudyPlanFeatureTests: XCTestCase {
    func testOnAppearLoadsPlanAndKanji() async {
        let store = TestStore(initialState: StudyPlanFeature.State()) {
            StudyPlanFeature()
        } withDependencies: {
            $0.userStore.loadPlan = { nil }
            $0.dictionaryClient.allKanji = { [.yama, .gaku] }
        }
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(.loaded(nil, [.yama, .gaku])) {
            $0.isLoading = false
            $0.kanji = [.yama, .gaku]
        }
    }

    func testCreatePlanDistributesAndSaves() async {
        let saved = LockIsolated<StudyPlan?>(nil)
        var initial = StudyPlanFeature.State()
        initial.kanji = [.yama, .gaku]
        let store = TestStore(initialState: initial) {
            StudyPlanFeature()
        } withDependencies: {
            $0.userStore.savePlan = { saved.setValue($0) }
        }
        let expected = StudyPlan(axisLabel: "学年", durationDays: 2,
                                 dayAssignments: [[1], [2]])
        await store.send(.createPlan(days: 2)) { $0.plan = expected }
        XCTAssertEqual(saved.value, expected)
    }

    func testMarkDoneUpdatesAndSaves() async {
        let saved = LockIsolated<StudyPlan?>(nil)
        var initial = StudyPlanFeature.State()
        initial.plan = StudyPlan(axisLabel: "学年", durationDays: 2,
                                 dayAssignments: [[1], [2]])
        let store = TestStore(initialState: initial) {
            StudyPlanFeature()
        } withDependencies: {
            $0.userStore.savePlan = { saved.setValue($0) }
        }
        await store.send(.markDone(1)) { $0.plan?.completedKanjiIDs.insert(1) }
        XCTAssertEqual(saved.value?.completedKanjiIDs, [1])
    }
}

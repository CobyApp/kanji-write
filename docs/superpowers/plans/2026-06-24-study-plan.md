# Study Plan & Progress — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a study-plan flow — create a 10/14/30-day plan, work through today's kanji (tap to write, mark done), and see persistent progress — surfaced as a second tab alongside the existing kanji browser.

**Architecture:** A new `StudyPlan` static-framework module holds pure scheduling (`PlanScheduler`), a `Codable` `StudyPlan` progress model, a persistent `UserStore` TCA dependency (JSON file), and `StudyPlanFeature`/`StudyPlanView`. A new `RootFeature`/`RootView` (in the `AppFeature` module) wraps the existing browse `AppFeature` and the new `StudyPlanFeature` in a `TabView`; the plan tab owns a navigation stack to the existing `KanjiWritingFeature`.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, TCA 1.26, GRDB 7.11, Tuist 4. App build/test on an iOS 26 iPad simulator (pick from `xcrun simctl list devices available | grep -i ipad`, e.g. `iPad Pro 11-inch (M5)`; use a UDID if the name is ambiguous). Run from repo root; `git` from repo root with `app/...` paths; never stage `*.xcworkspace`/`Derived/`.

Test command shape (used at every "verify" step):
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -12`

---

## File Structure (this slice)

```
app/
├── Project.swift                                  # + StudyPlan + StudyPlanTests; AppFeature dep (modify)
├── Sources/
│   ├── StudyPlan/
│   │   ├── PlanScheduler.swift                     # pure distribution (new)
│   │   ├── StudyPlan.swift                         # Codable model + progress (new)
│   │   ├── UserStore.swift                         # TCA dependency + JSON live (new)
│   │   ├── StudyPlanFeature.swift                  # TCA reducer (new)
│   │   └── StudyPlanView.swift                     # view (new)
│   ├── AppFeature/
│   │   ├── RootFeature.swift                       # TabView composition (new)
│   │   └── RootView.swift                          # TabView + plan nav stack (new)
│   └── KanjiApp/KanjiApp.swift                     # render RootView (modify)
└── Tests/
    └── StudyPlanTests/
        ├── PlanSchedulerTests.swift                 # (new)
        ├── StudyPlanModelTests.swift                # (new)
        ├── UserStoreTests.swift                     # (new)
        └── StudyPlanFeatureTests.swift              # (new)
```

`StudyPlan` module deps: `{SharedModels, DictionaryClient, ComposableArchitecture}`
(no `WritingCanvas` — navigation is the parent's job). `RootFeature`/`RootView`
live in `AppFeature`, which already depends on `KanjiListFeature` + `WritingCanvas`;
add `StudyPlan`. The existing browse `AppFeature` is unchanged.

---

## Task 1: StudyPlan module + PlanScheduler (TDD)

**Files:**
- Modify: `app/Project.swift`
- Create: `app/Sources/StudyPlan/PlanScheduler.swift`
- Create: `app/Tests/StudyPlanTests/PlanSchedulerTests.swift`

- [ ] **Step 1: Add the module + test target to Project.swift**

In `app/Project.swift`, add two targets (after `WritingCanvas`, before `KanjiApp`) and add `StudyPlanTests` to the scheme `testAction`:

```swift
        .target(
            name: "StudyPlan",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.studyplan",
            deploymentTargets: iOS,
            sources: ["Sources/StudyPlan/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "StudyPlanTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.studyplantests",
            deploymentTargets: iOS,
            sources: ["Tests/StudyPlanTests/**"],
            dependencies: [.target(name: "StudyPlan")]
        ),
```

testAction list becomes:
```swift
            testAction: .targets([
                "KanjiListFeatureTests",
                "DictionaryClientTests",
                "WritingCanvasTests",
                "StudyPlanTests",
            ])
```

- [ ] **Step 2: Write the failing test**

Create `app/Tests/StudyPlanTests/PlanSchedulerTests.swift`:

```swift
import XCTest

@testable import StudyPlan

final class PlanSchedulerTests: XCTestCase {
    func testEvenSplitWithRemainderGoesToEarlierBuckets() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2, 3, 4, 5, 6, 7, 8], days: 3),
            [[1, 2, 3], [4, 5, 6], [7, 8]])
    }

    func testDaysGreaterThanCountIsClampedToCount() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2], days: 5),
            [[1], [2]])
    }

    func testSingleDayHoldsEverything() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2, 3], days: 1),
            [[1, 2, 3]])
    }

    func testEmptyInputYieldsNoBuckets() {
        XCTAssertEqual(PlanScheduler.distribute(kanjiIDs: [], days: 3), [])
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run the test command. Expected: compile failure — `StudyPlan`/`PlanScheduler` not found.

- [ ] **Step 4: Implement the scheduler**

Create `app/Sources/StudyPlan/PlanScheduler.swift`:

```swift
/// Splits an ordered list of kanji ids into `days` buckets as evenly as
/// possible, with earlier buckets taking the remainder. Pure.
public enum PlanScheduler {
    public static func distribute(kanjiIDs: [Int], days: Int) -> [[Int]] {
        guard !kanjiIDs.isEmpty else { return [] }
        let bucketCount = min(max(days, 1), kanjiIDs.count)
        let base = kanjiIDs.count / bucketCount
        let remainder = kanjiIDs.count % bucketCount
        var buckets: [[Int]] = []
        var index = 0
        for day in 0..<bucketCount {
            let size = base + (day < remainder ? 1 : 0)
            buckets.append(Array(kanjiIDs[index..<index + size]))
            index += size
        }
        return buckets
    }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add app/Project.swift app/Sources/StudyPlan/PlanScheduler.swift app/Tests/StudyPlanTests/PlanSchedulerTests.swift
git commit -m "feat(app): StudyPlan module + PlanScheduler even distribution (TDD)"
```

---

## Task 2: StudyPlan model + progress (TDD)

**Files:**
- Create: `app/Sources/StudyPlan/StudyPlan.swift`
- Create: `app/Tests/StudyPlanTests/StudyPlanModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `app/Tests/StudyPlanTests/StudyPlanModelTests.swift`:

```swift
import XCTest

@testable import StudyPlan

final class StudyPlanModelTests: XCTestCase {
    private func plan(completed: Set<Int> = []) -> StudyPlan {
        StudyPlan(axisLabel: "学年", durationDays: 3,
                  dayAssignments: [[1, 2], [3, 4], [5]],
                  completedKanjiIDs: completed)
    }

    func testCurrentDayIsFirstIncompleteBucket() {
        XCTAssertEqual(plan().currentDayIndex, 0)
        XCTAssertEqual(plan(completed: [1, 2]).currentDayIndex, 1)
        XCTAssertEqual(plan(completed: [1, 2, 3, 4]).currentDayIndex, 2)
    }

    func testCurrentDayIsLastWhenAllDone() {
        XCTAssertEqual(plan(completed: [1, 2, 3, 4, 5]).currentDayIndex, 2)
    }

    func testTodaysKanjiAreTheCurrentBucket() {
        XCTAssertEqual(plan(completed: [1, 2]).todaysKanjiIDs, [3, 4])
    }

    func testProgressCounts() {
        let p = plan(completed: [1, 2, 3])
        XCTAssertEqual(p.totalCount, 5)
        XCTAssertEqual(p.completedCount, 3)
        XCTAssertEqual(p.progress, 0.6, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run the test command. Expected: compile failure — `StudyPlan` type not found.

- [ ] **Step 3: Implement the model**

Create `app/Sources/StudyPlan/StudyPlan.swift`:

```swift
/// A learner's active study plan and completion state. Pure value type.
public struct StudyPlan: Codable, Equatable {
    public var axisLabel: String
    public var durationDays: Int
    public var dayAssignments: [[Int]]
    public var completedKanjiIDs: Set<Int>

    public init(
        axisLabel: String,
        durationDays: Int,
        dayAssignments: [[Int]],
        completedKanjiIDs: Set<Int> = []
    ) {
        self.axisLabel = axisLabel
        self.durationDays = durationDays
        self.dayAssignments = dayAssignments
        self.completedKanjiIDs = completedKanjiIDs
    }

    public var totalCount: Int { dayAssignments.reduce(0) { $0 + $1.count } }
    public var completedCount: Int { completedKanjiIDs.count }
    public var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    /// The first day whose kanji are not all completed; the last day if every
    /// kanji is done. Pace-based — no calendar dependency.
    public var currentDayIndex: Int {
        for (index, day) in dayAssignments.enumerated()
        where day.contains(where: { !completedKanjiIDs.contains($0) }) {
            return index
        }
        return max(0, dayAssignments.count - 1)
    }

    public var todaysKanjiIDs: [Int] {
        guard !dayAssignments.isEmpty else { return [] }
        return dayAssignments[currentDayIndex]
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/StudyPlan/StudyPlan.swift app/Tests/StudyPlanTests/StudyPlanModelTests.swift
git commit -m "feat(app): StudyPlan model with pace-based progress (TDD)"
```

---

## Task 3: UserStore dependency (TDD)

**Files:**
- Create: `app/Sources/StudyPlan/UserStore.swift`
- Create: `app/Tests/StudyPlanTests/UserStoreTests.swift`

- [ ] **Step 1: Write the failing round-trip test**

Create `app/Tests/StudyPlanTests/UserStoreTests.swift`:

```swift
import Foundation
import XCTest

@testable import StudyPlan

final class UserStoreTests: XCTestCase {
    func testJSONFileRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "userstore-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = UserStore.jsonFile(at: dir.appending(path: "plan.json"))
        XCTAssertNil(await store.loadPlan())

        let plan = StudyPlan(axisLabel: "学年", durationDays: 2,
                             dayAssignments: [[1], [2]], completedKanjiIDs: [1])
        await store.savePlan(plan)

        XCTAssertEqual(await store.loadPlan(), plan)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run the test command. Expected: compile failure — `UserStore` not found.

- [ ] **Step 3: Implement the dependency**

Create `app/Sources/StudyPlan/UserStore.swift`:

```swift
import ComposableArchitecture
import Foundation

/// Persists the learner's active study plan. The seam behind which storage can
/// later become SwiftData; v1 is a single JSON file.
@DependencyClient
public struct UserStore: Sendable {
    public var loadPlan: @Sendable () async -> StudyPlan?
    public var savePlan: @Sendable (StudyPlan) async -> Void
}

extension UserStore {
    /// A store backed by a single JSON file at `url`.
    public static func jsonFile(at url: URL) -> UserStore {
        UserStore(
            loadPlan: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(StudyPlan.self, from: data)
            },
            savePlan: { plan in
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(plan) {
                    try? data.write(to: url)
                }
            }
        )
    }
}

extension UserStore: DependencyKey {
    public static let liveValue = UserStore.jsonFile(
        at: URL.applicationSupportDirectory.appending(path: "study_plan.json"))
}

extension UserStore: TestDependencyKey {
    public static let testValue = UserStore()
}

extension DependencyValues {
    public var userStore: UserStore {
        get { self[UserStore.self] }
        set { self[UserStore.self] = newValue }
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/StudyPlan/UserStore.swift app/Tests/StudyPlanTests/UserStoreTests.swift
git commit -m "feat(app): UserStore dependency with JSON persistence (TDD)"
```

---

## Task 4: StudyPlanFeature (TDD)

**Files:**
- Create: `app/Sources/StudyPlan/StudyPlanFeature.swift`
- Create: `app/Tests/StudyPlanTests/StudyPlanFeatureTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `app/Tests/StudyPlanTests/StudyPlanFeatureTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run the test command. Expected: compile failure — `StudyPlanFeature` not found.

- [ ] **Step 3: Implement the reducer**

Create `app/Sources/StudyPlan/StudyPlanFeature.swift`:

```swift
import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct StudyPlanFeature {
    @ObservableState
    public struct State: Equatable {
        public var plan: StudyPlan?
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var isLoading = false
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case loaded(StudyPlan?, [Kanji])
        case createPlan(days: Int)
        case markDone(Int)
        case kanjiTapped(Kanji)
    }

    @Dependency(\.userStore) var userStore
    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                return .run { send in
                    async let plan = userStore.loadPlan()
                    let kanji = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.loaded(await plan, kanji))
                }
            case let .loaded(plan, kanji):
                state.isLoading = false
                state.plan = plan
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                return .none
            case let .createPlan(days):
                let assignments = PlanScheduler.distribute(
                    kanjiIDs: state.kanji.map(\.id), days: days)
                let plan = StudyPlan(axisLabel: "学年", durationDays: days,
                                     dayAssignments: assignments)
                state.plan = plan
                return .run { _ in await userStore.savePlan(plan) }
            case let .markDone(id):
                guard var plan = state.plan else { return .none }
                plan.completedKanjiIDs.insert(id)
                state.plan = plan
                return .run { [plan] _ in await userStore.savePlan(plan) }
            case .kanjiTapped:
                return .none
            }
        }
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/StudyPlan/StudyPlanFeature.swift app/Tests/StudyPlanTests/StudyPlanFeatureTests.swift
git commit -m "feat(app): StudyPlanFeature load/create/markDone (TDD)"
```

---

## Task 5: StudyPlanView (build-verified)

**Files:**
- Create: `app/Sources/StudyPlan/StudyPlanView.swift`

- [ ] **Step 1: Implement the view**

Create `app/Sources/StudyPlan/StudyPlanView.swift`:

```swift
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
        VStack(spacing: 0) {
            ProgressView(value: plan.progress) {
                Text("進捗 \(plan.completedCount) / \(plan.totalCount)")
            }
            .padding()
            List {
                Section("今日の漢字 (Day \(plan.currentDayIndex + 1))") {
                    ForEach(plan.todaysKanjiIDs, id: \.self) { id in
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
```

- [ ] **Step 2: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` (build + existing tests green).

- [ ] **Step 3: Commit**

```bash
git add app/Sources/StudyPlan/StudyPlanView.swift
git commit -m "feat(app): StudyPlanView (create plan, today's kanji, progress)"
```

---

## Task 6: Root TabView + navigation

**Files:**
- Modify: `app/Project.swift` (AppFeature depends on StudyPlan)
- Create: `app/Sources/AppFeature/RootFeature.swift`
- Create: `app/Sources/AppFeature/RootView.swift`
- Modify: `app/Sources/KanjiApp/KanjiApp.swift`

- [ ] **Step 1: Add the StudyPlan dependency to AppFeature**

In `app/Project.swift`, the `AppFeature` target `dependencies` array — add
`.target(name: "StudyPlan")` so it reads:

```swift
            dependencies: [
                .target(name: "KanjiListFeature"),
                .target(name: "WritingCanvas"),
                .target(name: "StudyPlan"),
                .external(name: "ComposableArchitecture"),
            ]
```

- [ ] **Step 2: Implement the root reducer**

Create `app/Sources/AppFeature/RootFeature.swift`:

```swift
import ComposableArchitecture
import StudyPlan
import WritingCanvas

@Reducer
public struct RootFeature {
    @ObservableState
    public struct State: Equatable {
        public var selectedTab: Tab = .browse
        public var browse = AppFeature.State()
        public var plan = StudyPlanFeature.State()
        public var planPath = StackState<KanjiWritingFeature.State>()
        public init() {}

        public enum Tab: Equatable { case browse, plan }
    }

    // StackActionOf<KanjiWritingFeature> is not Equatable, so Action intentionally omits Equatable.
    public enum Action {
        case tabSelected(State.Tab)
        case browse(AppFeature.Action)
        case plan(StudyPlanFeature.Action)
        case planPath(StackActionOf<KanjiWritingFeature>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.browse, action: \.browse) { AppFeature() }
        Scope(state: \.plan, action: \.plan) { StudyPlanFeature() }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            case let .plan(.kanjiTapped(kanji)):
                state.planPath.append(KanjiWritingFeature.State(kanji: kanji))
                return .none
            case .browse, .plan, .planPath:
                return .none
            }
        }
        .forEach(\.planPath, action: \.planPath) {
            KanjiWritingFeature()
        }
    }
}
```

- [ ] **Step 3: Implement the root view**

Create `app/Sources/AppFeature/RootView.swift`:

```swift
import ComposableArchitecture
import StudyPlan
import SwiftUI
import WritingCanvas

public struct RootView: View {
    @Bindable public var store: StoreOf<RootFeature>

    public init(store: StoreOf<RootFeature>) {
        self.store = store
    }

    public var body: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            AppView(store: store.scope(state: \.browse, action: \.browse))
                .tabItem { Label("一覧", systemImage: "list.bullet") }
                .tag(RootFeature.State.Tab.browse)

            NavigationStack(
                path: $store.scope(state: \.planPath, action: \.planPath)
            ) {
                StudyPlanView(store: store.scope(state: \.plan, action: \.plan))
            } destination: { store in
                KanjiWritingView(store: store)
            }
            .tabItem { Label("プラン", systemImage: "calendar") }
            .tag(RootFeature.State.Tab.plan)
        }
    }
}
```

- [ ] **Step 4: Render RootView from the app entry**

Overwrite `app/Sources/KanjiApp/KanjiApp.swift`:

```swift
import AppFeature
import ComposableArchitecture
import SwiftUI

@main
struct KanjiApp: App {
    @MainActor static let store = Store(initialState: RootFeature.State()) {
        RootFeature()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: KanjiApp.store)
        }
    }
}
```

- [ ] **Step 5: Generate, build, and run the full suite**

Run the test command. Expected: `** TEST SUCCEEDED **` — PlanScheduler (4), StudyPlanModel (4), UserStore (1), StudyPlanFeature (3), plus existing SVGPath (7), KanjiWritingFeature (2), KanjiListFeature (2), DictionaryClient (2). App builds with the two-tab root.

- [ ] **Step 6: Commit**

```bash
git add app/Project.swift app/Sources/AppFeature/RootFeature.swift app/Sources/AppFeature/RootView.swift app/Sources/KanjiApp/KanjiApp.swift
git commit -m "feat(app): two-tab root (browse + study plan) with plan nav stack"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `PlanScheduler` (spec §3) → Task 1; `StudyPlan` model +
  progress (§3/§4) → Task 2; `UserStore` (§3) → Task 3; `StudyPlanFeature` (§3)
  → Task 4; `StudyPlanView` (§3) → Task 5; `RootFeature`/`RootView` TabView +
  plan nav (§3/§5) → Task 6; tests (§7) across Tasks 1–4.
- **Spec correction recorded:** the `StudyPlan` module does NOT depend on
  `WritingCanvas` (navigation is handled by `RootFeature` in the `AppFeature`
  module). Spec §6 mentioned `WritingCanvas`; the plan drops it.
- **Type consistency:** `PlanScheduler.distribute(kanjiIDs:days:)`,
  `StudyPlan(axisLabel:durationDays:dayAssignments:completedKanjiIDs:)` and its
  computed props (`currentDayIndex`/`todaysKanjiIDs`/`progress`/`completedCount`/
  `totalCount`), `UserStore.{loadPlan,savePlan,jsonFile(at:)}`,
  `StudyPlanFeature.Action` (`onAppear`/`loaded`/`createPlan`/`markDone`/
  `kanjiTapped`), and `RootFeature` (`selectedTab`/`browse`/`plan`/`planPath`)
  are used identically across tasks.
- **Manual QA flagged:** TabView visuals, picker, and list interactions are
  verified by hand; only the build proves they compile and the reducers/tests
  prove the logic.

## Follow-on (not in this plan)

Calendar-based pacing + reminders, SRS review, SwiftData-backed `UserStore`,
drawing persistence, plan editing/deletion, the real full `kanji.sqlite`.

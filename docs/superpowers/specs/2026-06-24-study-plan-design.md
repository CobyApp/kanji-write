# Study Plan & Progress — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: app scaffold + writing canvas (merged)

## 1. Purpose

Let the learner commit to a plan ("finish in 10 / 14 / 30 days"), have the kanji
distributed across days, and work through a daily set — tapping a kanji to write
it and marking it done — with progress that persists across launches. This is
the other half of the app's value alongside the writing canvas.

## 2. Scope & Non-Goals

In scope:
- Pure plan scheduling (`PlanScheduler`) and a `StudyPlan` progress model.
- A persistent `UserStore` (TCA dependency) holding the active plan.
- `StudyPlanFeature` + `StudyPlanView`: create a plan, see today's kanji, mark
  done, view overall progress, tap a kanji → writing screen.
- App becomes a two-tab `TabView` (一覧 = existing browse; プラン = study plan).

Non-goals (follow-on):
- Calendar/clock-based pacing or notifications (v1 progression is pace-based,
  not date-based — see §4).
- SRS review scheduling.
- Migrating `UserStore` to SwiftData (the dependency seam allows it later).
- Drawing persistence, multiple concurrent plans, plan editing/deletion.

## 3. Components (each one responsibility)

- **`PlanScheduler`** (in a new `StudyPlan` module) —
  `distribute(kanjiIDs: [Int], days: Int) -> [[Int]]`: splits the ordered ids
  into `days` buckets as evenly as possible, earlier buckets taking the
  remainder (8 ids / 3 days → `[[3 ids],[3],[2]]`). `days` is clamped to
  `1...max(1, count)`. Pure, precisely unit-testable.
- **`StudyPlan`** (value type, `Codable`, `Equatable`) — `axisLabel: String`
  (informational, e.g. "学年" / "JLPT"), `durationDays: Int`,
  `dayAssignments: [[Int]]`, `completedKanjiIDs: Set<Int>`. Computed:
  - `currentDayIndex`: first day whose kanji are not all completed (or the last
    day if every kanji is done) — **pace-based, no clock dependency**.
  - `todaysKanjiIDs: [Int]` = `dayAssignments[currentDayIndex]`.
  - `completedCount` / `totalCount` / `progress: Double`.
- **`UserStore`** (TCA dependency) — `loadPlan: () async -> StudyPlan?`,
  `savePlan: (StudyPlan) async -> Void`. `liveValue` reads/writes one JSON file
  in `applicationSupportDirectory`; `testValue`/`previewValue` are in-memory.
- **`StudyPlanFeature`** (TCA `@Reducer`) — State `{plan: StudyPlan?,
  kanji: IdentifiedArrayOf<Kanji>, isLoading}`; Action `{onAppear,
  loaded(StudyPlan?, [Kanji]), createPlan(days: Int), markDone(Int),
  kanjiTapped(Kanji)}`. `onAppear` loads the saved plan + `allKanji`;
  `createPlan` builds via `PlanScheduler`, saves, sets state; `markDone` inserts
  into `completedKanjiIDs` and saves; `kanjiTapped` is handled by the parent for
  navigation.
- **`StudyPlanView`** — no plan: a duration picker (10/14/30) + "プラン作成";
  with plan: an overall progress bar + a "今日の漢字" list whose rows show the
  literal, a done toggle (sends `markDone`), and tap-to-write (sends
  `kanjiTapped`).
- **`RootFeature`** + **`RootView`** — `RootFeature` composes
  `{selectedTab, browse: AppFeature, plan: StudyPlanFeature}`. `RootView` is a
  `TabView` of the existing `AppView` (一覧) and `StudyPlanView` (プラン). The
  plan tab owns a `StackState<KanjiWritingFeature.State>` so tapping a kanji
  pushes the writing screen (reusing `KanjiWritingFeature`).

## 4. Progress semantics (v1)

Progression is **pace-based, not date-based**, to avoid a clock dependency:
"today's kanji" is the first day-bucket that still has an incomplete kanji. The
learner advances by completing kanji, not by the calendar. "Finish in 10 days"
therefore means "10 day-buckets to complete at your pace" in v1; calendar pacing
and reminders are a follow-on.

## 5. Data flow

`StudyPlanView` onAppear → `UserStore.loadPlan()` + `DictionaryClient.allKanji()`
→ state. Create → `PlanScheduler.distribute(allKanji.ids, days)` → `StudyPlan`
→ `UserStore.savePlan` → state. Mark done → mutate `completedKanjiIDs` →
`savePlan` → recomputed progress. Tap → `RootFeature` pushes
`KanjiWritingFeature(kanji)` on the plan tab's stack.

## 6. Module / dependency graph

New `StudyPlan` module → `{SharedModels, DictionaryClient, WritingCanvas, TCA}`
(`WritingCanvas` for `KanjiWritingFeature` on the plan's nav stack). `UserStore`
lives in the `StudyPlan` module (or a small `UserStore` module; v1 keeps it in
`StudyPlan` for simplicity). New `RootFeature`/`RootView` (in `AppFeature`
module, which already depends on `KanjiListFeature` + `WritingCanvas`; add
`StudyPlan`). `KanjiApp` renders `RootView`. Existing `AppFeature` (browse) is
unchanged and becomes the 一覧 tab. No cycles.

## 7. Testing

- **`PlanSchedulerTests`**: even split incl. remainder distribution; `days` > or
  < count clamped; empty input.
- **`StudyPlanTests`**: `currentDayIndex` (none done → 0; first bucket done →
  1; all done → last), `todaysKanjiIDs`, `progress`.
- **`StudyPlanFeatureTests`** (`TestStore`, mocked `userStore` + `dictionaryClient`):
  `onAppear` loads; `createPlan` distributes + calls `savePlan`; `markDone`
  marks + calls `savePlan`.
- **`UserStore` live**: a round-trip test (save then load returns an equal plan)
  using a temp directory.
- Build verification: `tuist generate` + `xcodebuild test` on an iOS 26
  simulator, green. TabView/navigation compile-verified; visuals are manual QA.

## 8. Build order (this slice)

1. `StudyPlan` module + `PlanScheduler` (TDD).
2. `StudyPlan` model + progress computed properties (TDD).
3. `UserStore` dependency (interface + JSON live) + round-trip test.
4. `StudyPlanFeature` reducer (TDD with mocked deps).
5. `StudyPlanView` (build-verified).
6. `RootFeature` + `RootView` (TabView + plan nav stack) + `KanjiApp` entry;
   full build/test green.

Gets its own implementation plan. Follow-on: calendar pacing, SRS, SwiftData,
drawing persistence.

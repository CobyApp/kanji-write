# SRS (Spaced Repetition) — Design

Date: 2026-06-27
Status: Approved (delegated) — ready for implementation planning
Builds on: study-plan slice + the bundled DB.

## 1. Purpose

Add spaced-repetition review: kanji become "due" on a Leitner schedule, the app
surfaces today's due kanji, and grading each (got it / again) advances or resets
its interval. A third 復習 tab.

## 2. Scope & Non-Goals

In scope:
- Pure Leitner scheduling functions (interval, advance, is-due) — unit-tested.
- `ReviewRecord` model + a persistent `ReviewStore` dependency.
- `ReviewFeature`/`ReviewView`: load records + kanji + today (clock), show due
  kanji, grade them.
- A 復習 tab in the root TabView.

Non-goals (follow-on):
- Linking grading to the writing canvas (manual 正解/もう一度 buttons for now);
  statistics/streaks; SM-2; seeding which kanji enter review (any graded kanji
  is tracked; an "add to review" entry point is a follow-on — for v1 the review
  set is whatever has a `ReviewRecord`, plus a way to start: see §3).

## 3. Components

- **Pure SRS** (in a new `Review` module, `SRS.swift`):
  - `srsIntervalDays(box: Int) -> Int` → Leitner ladder `[1, 2, 4, 7, 15, 30]`
    (box clamped to the last rung).
  - `srsAdvance(box: Int, correct: Bool) -> Int` → `min(box+1, 5)` if correct,
    else `0`.
  - `srsIsDue(box: Int, lastReviewedDay: Int, today: Int) -> Bool` →
    `today - lastReviewedDay >= srsIntervalDays(box)`.
  All pure, day-integer based, precisely unit-testable.
- **`ReviewRecord`** (`SharedModels`): `{ kanjiID: Int, box: Int,
  lastReviewedDay: Int }`, `Codable`/`Equatable`/`Identifiable (id = kanjiID)`.
- **`ReviewStore`** (`@DependencyClient`, `Review` module): `loadRecords:
  () async -> [ReviewRecord]`, `saveRecords: ([ReviewRecord]) async -> Void`.
  JSON file under `applicationSupportDirectory`; `directory(_:)` factory for tests.
- **`ReviewFeature`** (`@Reducer`): `State { records: IdentifiedArrayOf<ReviewRecord>,
  kanji: IdentifiedArrayOf<Kanji>, today: Int, isLoading }`. `onAppear` loads
  records + `allKanji` + computes `today` from `@Dependency(\.date)`
  (`Int(now.timeIntervalSince1970 / 86_400)`). `grade(kanjiID, correct)` updates
  the record (`srsAdvance`, `lastReviewedDay = today`; creating one at box per
  result if absent) and persists via `ReviewStore`. A computed
  `dueKanji: [Kanji]` = kanji whose record `srsIsDue(..., today)` (a kanji with
  **no** record counts as due — new cards).
- **`ReviewView`**: lists `dueKanji` (literal + 正解 / もう一度 buttons sending
  `grade`); empty → "今日の復習はありません".
- **Root nav**: `RootFeature` adds `review: ReviewFeature.State` and a `.review`
  tab; `RootView` adds a third `復習` tab (calendar.badge.clock icon). Browse/plan
  stacks untouched.

## 4. Data flow

`onAppear` → `ReviewStore.loadRecords()` + `DictionaryClient.allKanji()` + clock
→ state. `dueKanji` derives from records + today (pure). `grade` → update record
→ `ReviewStore.saveRecords`.

## 5. Testing

- **SRS functions**: interval ladder incl. clamp; advance correct/incorrect;
  is-due boundary (exactly-due, not-yet, overdue, never-reviewed).
- **`ReviewStore`**: save→load round-trip in a temp dir; empty load → `[]`.
- **`ReviewFeature`** (`TestStore`, `$0.date = .constant(...)`, mocked store +
  client): `onAppear` populates records/kanji/today; `grade(correct)` advances
  the box and calls `saveRecords` (verified via `LockIsolated`); a new kanji
  (no record) is in `dueKanji`.
- Build verification green; the tab UI is manual QA.

## 6. Build order

1. Pure SRS funcs (`Review/SRS.swift`) + `ReviewRecord` (`SharedModels`) +
   unit tests.
2. `ReviewStore` dependency + round-trip test.
3. `ReviewFeature` (TDD with clock/store/client deps).
4. `ReviewView` + 復習 tab in `RootFeature`/`RootView` (build-verified).

## 7. Follow-on

Tie grading to writing; "add to review" from the study card; stats/streaks; SM-2.

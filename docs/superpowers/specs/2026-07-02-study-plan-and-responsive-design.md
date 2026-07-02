# Study Plan + Responsive Writing Grid + iPhone-no-writing — Design

Date: 2026-07-02
Status: Approved (user: single-level plan; small responsive write cells; iPhone
drops writing).

## 1. Study plan (single level)

A plan = **target JLPT level** + **new kanji/day**, both `@AppStorage`
(`targetLevel` default "N5", `newPerDay` default 7). New kanji for 学習/テ스트 are
drawn only from `targetLevel`, in stroke-count order, excluding already-tracked
ones. When the level is exhausted the user picks the next.

Pure logic (Review/Curriculum, TDD):
- `studyOrder(_ kanji:, level: String? = nil)` — existing order, optionally
  filtered to one `jlptLevel`.
- `remainingNew(order:, records:) -> Int` — items in `order` with no record.
- `daysToFinish(remaining:, perDay:) -> Int` — `ceil(remaining/perDay)`, 0 if
  perDay ≤ 0.

設定 gains a **학습 플랜** card: a target-level picker (N5…N1), the existing
per-day stepper, and a finish read-out — "남은 N자 · 하루 M자 · 약 D일" plus the
projected date (view formats `today + D days`). The 学習 hub header shows a
compact "N5 · 하루 7자 · D-nn".

## 2. Responsive writing grid (fills width, small cells)

New reusable `TracingGrid` in **WritingCanvas**: an adaptive `LazyVGrid`
(`GridItem(.adaptive(minimum: ~120))`) of small square cells, each a faint
stroke-order guide behind an independent `PencilCanvasView`. Column count and
cell size follow the available width (fills wide iPad, fewer columns when
narrow). A shared "지우기/가이드" control clears/toggles all cells.

- **Practice (練習)** uses `TracingGrid` (replaces its bespoke 2-col grid).
- **Worksheet (学習)** "써보세요" step switches from one large canvas to a small
  `TracingGrid` (a handful of cells), so a big iPad isn't one giant box.
Both scroll and fill the full width.

## 3. iPhone (compact) drops writing

Writing is an iPad/Apple-Pencil activity. On `horizontalSizeClass == .compact`:
- **学習** worksheet shows the stroke-order animation + word + example but **no
  TracingGrid** (learn by watching + reading).
- **練習** tab is **hidden** on iPhone (pure writing).
- **テスト** uses a **flip card** (meaning → tap → reveal reading/kanji →
  合格/不合格), no canvas; on iPad it keeps write-to-recall.
- iPhone tabs: 学習 / テスト / 一覧 / 設定 (no 練習). iPad sidebar unchanged
  (keeps 練習 + writing everywhere).

Mode views read `@Environment(\.horizontalSizeClass)` and branch. RootView's
compact `TabView` omits the `.practice` tab.

## 4. Testing

- Curriculum: `studyOrder(level:)` filters correctly; `remainingNew`,
  `daysToFinish` (incl. perDay 0, exact/round-up). TDD.
- Existing tests stay green (studyOrder no-arg unchanged via default level nil).
- Visual: iPad sim (full-width grids, plan card, hub summary) + an iPhone sim
  (no write grid, no 練習 tab, test flip).

## 5. Non-goals

Multi-level/cumulative plans, streaks/stats, editable schedules. Single level +
per-day + finish estimate only.

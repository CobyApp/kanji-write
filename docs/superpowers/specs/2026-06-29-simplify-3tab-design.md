# Simplify to 3 Tabs + Settings-Driven Classification — Design

Date: 2026-06-29
Status: Approved (user: "3탭 통합", default classification JLPT)
Builds on: the kawaii pastel redesign. Reorganizes the IA; no feature loss.

## 1. Purpose

The app has four tabs (一覧 / プラン / 復習 / 設定) and a 12-chip filter row on
browse. Consolidate to **three tabs**, move the grade↔JLPT choice into Settings,
replace the chip clutter with a clean level drill-down, and calm the visuals.
All existing capabilities are preserved — only reorganized.

## 2. New information architecture (3 tabs)

1. **学習 (Study)** — merges プラン + 復習 into one daily hub.
2. **一覧 (Browse)** — level drill-down driven by the Settings classification.
3. **設定 (Settings)** — classification toggle + language + reminder.

## 3. Classification (Settings-driven)

- New `Classification` enum in SharedModels: `.jlpt` / `.grade`, with display
  labels (JLPT別 / 学年別). Persisted via `@AppStorage("classification")`,
  default `.jlpt`.
- 設定 gains a segmented **分類** picker above 言語 and リマインダー.

## 4. 一覧 — level drill-down

- Pure helpers (in KanjiListFeature, TDD): `levels(for: Classification) -> [KanjiLevel]`
  and `kanji(_ all:, in: KanjiLevel) -> [Kanji]`.
  - JLPT levels: N5, N4, N3, N2, N1.
  - Grade levels: 小1…小6 (grade 1–6), 中学 (grade 8). A `KanjiLevel` carries a
    display label + the predicate (jlptLevel == / grade ==).
- KanjiListFeature state: `kanji`, `isLoading`, `loadError`, `selectedLevel:
  KanjiLevel?`, `searchText`. Actions: `levelSelected`, `levelCleared`,
  `searchChanged` (+ existing load/tap).
  - `searchText` non-empty → show search results across ALL kanji (level ignored).
  - else `selectedLevel == nil` → show the level cards (each with its kanji count).
  - else → show the kanji in that level, with a back-to-levels control.
- View reads `@AppStorage("classification")` to pick which levels to show.
- Search predicate reuses the existing reading/literal match.

## 5. 学習 — plan + review hub

- New `StudyHubView` (in AppFeature, which already imports StudyPlan + Review +
  KanjiDetail + WritingCanvas) composing the two existing stores. No new reducer;
  StudyPlanFeature and ReviewFeature are unchanged except a small addition below.
- Layout (one NavigationStack, cream background, section cards):
  - Plan progress card, or "プラン作成" (10/14/30) when no plan.
  - **今日学ぶ**: today's scheduled kanji (plan) with done checkmarks.
  - **復習**: due SRS cards (正解 / もう一度).
  - Tapping any kanji → push detail → 書いて練習 (reuses the existing `planPath`
    StackState + Path enum).
- `ReviewFeature` gains a `kanjiTapped(Kanji)` action (currently it only grades);
  RootFeature routes it to `planPath.append(.detail(...))`, same as plan taps.
- The standalone `StudyPlanView` and `ReviewView` tab usages are removed; their
  reducers live on. (Old view files removed to avoid dead code.)

## 6. RootFeature / RootView

- `Tab` enum → `.browse, .study, .settings` (was browse/plan/review/settings).
- RootView: 3 `TabView` tabs. 学習 tab = `NavigationStack(path: planPath)` hosting
  `StudyHubView`; 一覧 and 設定 as before (minus the removed review tab).
- Keep `.tint(Palette.accent)` and the locale environment.

## 7. Calmer visuals

- Drop per-row rainbow rotation. Color is applied at the **level/section** scope:
  one accent per level (its cards/glyph tiles share that level's color), and each
  学習/設定 section keeps a single accent. More whitespace, less color noise.
  Kawaii pastel base stays.

## 8. Testing

- Pure logic (TDD): `levels(for:)` for both classifications (correct levels,
  labels, order); `kanji(in:)` (correct membership, grade-8 = 中学 bucket); search
  predicate unchanged. New tests in `KanjiListFeatureTests`.
- Visual: build + run on the iOS 26.5 simulator, screenshot each tab + drill-down.
- Existing app tests stay green (AppFeature tab routing updated for 3 tabs).

## 9. Non-goals

No new learning mechanics, no zh-Hant, no dark-mode tuning. Reorganization +
classification setting + calmer visuals only.

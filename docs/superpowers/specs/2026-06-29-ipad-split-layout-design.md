# iPad 3-Column Layout (NavigationSplitView) — Design

Date: 2026-06-29
Status: Approved (user chose the full NavigationSplitView restructure).
Builds on: 3-tab IA, FSRS engine, cute fonts. Replaces the app shell; all
features are preserved, only the navigation/layout changes.

## 1. Purpose

Use the iPad's width: replace the TabView + NavigationStack shell with a
3-column `NavigationSplitView` (sidebar │ content │ detail). On compact widths
(iPhone, Slide Over) the columns collapse automatically.

## 2. Columns

- **Sidebar**: a search field, then sections — **学習** (today's FSRS session),
  **一覧** with one row per level (from the 設定 classification: N5…N1 or 小1…中学),
  and **設定**. Selecting a row drives the content column.
- **Content**: depends on sidebar selection (or search):
  - search active → kanji search results.
  - `.study` → FSRS session (今日のセッション summary + 復習 + 新規, 4-button grading).
  - `.level(id)` → the kanji in that level (cards).
  - `.settings` → classification / new-per-day / language / reminder.
  - selecting a kanji here sets the detail column.
- **Detail** (widest): the selected kanji — big glyph + readings + gloss + grade/
  JLPT chips, a **large inline writing canvas** (stroke guide + 採点), and below
  it 活用 / 例文 / 関連. Per-language fonts (Jua/ZCOOL) apply to the meaning text.
  Empty state when nothing is selected.

## 3. Architecture (TCA)

`RootFeature` is rebuilt around split-view state:
- Keeps `review: ReviewFeature.State` as the data + session owner (it already
  loads kanji + records + today and runs FSRS grading) and
  `reminder: ReminderFeature.State` for settings.
- Adds `sidebar: SidebarSelection? = .study` (`.study | .settings | .level(String)`),
  `searchText: String`, and the selected-kanji detail: `detail:
  KanjiDetailFeature.State?` + `writing: KanjiWritingFeature.State?`.
- Drops the `browse` (AppFeature/KanjiListFeature) and `plan` scopes — the
  sidebar+content replace the old browse tab, and the FSRS session replaces the
  plan tab. (KanjiListFeature/AppFeature/StudyPlan code may remain in-repo but
  is no longer wired into the shell; remove the now-dead view wiring.)
- Actions: `review`, `reminder`, `sidebarSelected`, `searchChanged`,
  `kanjiSelected(Kanji)` (sets `detail` + `writing`), `detail(…)`, `writing(…)`.
- Level lists, search results, and the session are computed in the views from
  `review.kanji` / `review.records` via the existing pure functions
  (`levels(for:)`, `kanjiIn`, `searchMatches`, `studyOrder`, `todaysSession`).

`RootView` uses `NavigationSplitView { sidebar } content: { … } detail: { … }`.
The detail column composes `KanjiDetailView` content + an inline
`KanjiWritingView`; the old "書いて練習" push is gone (canvas is always inline),
and 復習に追加 becomes an inline button. Grading buttons in the session content
send `review.grade`.

## 4. Reuse / change

- Reuse unchanged: ReviewFeature (FSRS), KanjiDetailFeature, KanjiWritingFeature,
  ReminderFeature, DesignSystem, all pure logic.
- `KanjiDetailView` is refactored so its sections can render inside the detail
  column (no NavigationStack toolbar dependency); the writing canvas sits inline.
- `Font.kawaii(_:language:)` applied to detail gloss / word meaning / sentence
  translation.

## 5. Testing

- RootFeature reducer tests: sidebar selection, search, kanjiSelected sets
  detail+writing, review/grade routing. (TCA TestStore.)
- Existing pure-logic + feature tests stay green.
- Visual: simulator screenshots at iPad width (3 columns) and a narrow width
  (collapsed) to confirm responsive behavior.

## 6. Non-goals

No new learning features; no change to FSRS/curriculum. Shell + layout +
per-language detail fonts only. iPhone polish beyond automatic column collapse
is out of scope (the app targets iPad).

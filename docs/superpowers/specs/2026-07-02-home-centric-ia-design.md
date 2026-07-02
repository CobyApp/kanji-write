# Home-Centric IA + Full-Screen Study Sessions — Design

Date: 2026-07-02
Status: Approved (user: home-centric 3 destinations; study is a full-screen
immersive session; words absorbed into the dictionary).

## 1. Purpose

Consolidate six top-level destinations (学習/練習/テスト/単語/一覧/設定) into three,
and make studying an immersive **full-screen session** (no sidebar/tab chrome).

## 2. Three destinations

- **홈/오늘 (Home)** — the landing dashboard:
  - Plan summary card: target level · new/day · remaining · ~finish days
    ("N5 · 7/日 · 79 left · ~12d").
  - Big **학습 시작** → full-screen Worksheet session.
  - **복습 N개** → full-screen Test session (N = due count; disabled at 0).
  - **연습** → full-screen Practice session (iPad only; hidden on iPhone).
  - Small stats (습득/오늘 신규).
- **사전 (Dictionary)** — reference: level browse (N5…N1) + search + kanji detail
  (drill to word detail and back) + **단어장** (the wordbook / word review is
  reached here, not as a top-level item).
- **설정 (Settings)** — plan (target level + new/day) + language + reminder.

## 3. Full-screen sessions

`Session` is a `@Reducer enum { worksheet(WorksheetFeature); test(TestFeature);
practice(PracticeFeature) }`, held as `@Presents var session` on RootFeature.
Home actions set it; RootView shows it in a `.fullScreenCover` — a
`NavigationStack` wrapping the session view with a single **✕ (닫기)** toolbar
button that clears `session` and returns to Home. No sidebar/tabs while studying.
(The session features are unchanged; they just move from always-present scopes
into the presented `session`.)

## 4. Shell

- **RootFeature**: destinations `home / dictionary / settings` (Tab + Sidebar);
  keep `review` (data: kanji/records/today — powers Home's plan summary + due
  count) + `wordReview` (wordbook, reached from 사전) + `reminder` + the `path`
  nav stack (dictionary drill). Add `@Presents session`. Home actions:
  `startStudy` → `.worksheet`, `startReview` → `.test`, `startPractice` →
  `.practice`.
- **RootView**:
  - compact (iPhone): TabView 오늘 / 사전 / 설정.
  - regular (iPad): NavigationSplitView sidebar 오늘 / 사전(levels) / 설정 →
    content; detail column keeps the dictionary drill.
  - Both attach `.fullScreenCover(item: $store.scope(state: \.$session, …))`.
- **HomeView** (new, AppFeature): the dashboard above; reads `review` for the
  plan summary + due count; buttons send the launch actions.

## 5. Reuse / change

Reuse unchanged: WorksheetFeature/TestFeature/PracticeFeature, ReviewFeature (as
data), WordReviewFeature (wordbook), ReminderFeature, KanjiDetail/WordDetail,
the dictionary browse (KanjiCardList, levels/search). New: HomeView + `Session`
enum + fullScreenCover wiring. Removed: 学習/練習/テスト/単語 as top-level tabs
(they become Home-launched sessions / dictionary sub-content). iPhone still omits
writing (worksheet no grid, practice session not offered, test = flip).

## 6. Testing

- RootFeature: launching each session sets `session`; closing clears it;
  destination switching. TDD (TestStore).
- Existing feature/pure tests stay green.
- Visual: iPad (home dashboard, launch → full-screen session, ✕ back) + iPhone
  (3 tabs, no practice launch, test flip).

## 7. Non-goals

Streaks/stats history, multi-plan, onboarding. Home dashboard + full-screen
sessions + 3-destination shell only.

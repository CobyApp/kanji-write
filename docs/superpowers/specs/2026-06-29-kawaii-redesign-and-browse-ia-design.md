# Kawaii Pastel Redesign + Browse IA Cleanup — Design

Date: 2026-06-29
Status: Approved (direction confirmed by user: kawaii pastel, full scope)

## 1. Purpose

The app currently uses entirely system-default styling (plain `List`, black
text, no theme) and a flat, unnavigable 2,136-kanji browse list. An orphan
`Sources/DesignSystem/Palette.swift` (untracked, no target, unused) defined a
kawaii pastel palette but was never wired in.

This work does two things together:

1. **Apply a kawaii pastel visual system across every screen.**
2. **Tidy the feature/IA**: make the browse list navigable (filter + search),
   and move the language selector to where it belongs (Settings).

No business logic changes beyond browse filtering/search. Data, persistence,
SRS, reminders, recognition, and navigation flow are untouched.

## 2. DesignSystem module (foundation)

Promote `Sources/DesignSystem/` to a real Tuist `.staticFramework` target that
every UI module depends on.

- **Palette** (existing, kept): cream-pink background `#FFF6FA`, white cards,
  five pastel accent pairs (pink/mint/lavender/butter/sky) cycled per index,
  warm ink `#6B5563` (never pure black), candy-pink accent `#FF80B5`.
- **Reusable view pieces** (new, small + focused):
  - `RoundedCard` — white surface, corner radius 20, soft shadow, padding.
  - `CandyChip(text, tint)` — colored pill for grade/JLPT badges + filter chips.
  - `PastelTile(text, tint)` — rounded colored tile holding a large kanji.
  - `Font` helper for the app's rounded type (`.system(..., design: .rounded)`).
- Each piece: one clear purpose, pure SwiftUI, no feature dependency, snapshot-
  testable by eye in the simulator.

## 3. Browse (一覧) — biggest change

- Replace plain `List` with a scroll of **kanji cards** (`RoundedCard` +
  `PastelTile` for the glyph, color rotation by index), readings in rounded ink.
- **Filter chips** row (horizontal scroll) at top: `すべて` / JLPT `N5…N1` /
  grade `小1…小6` `中` (`CandyChip`, selected state highlighted). Filtering uses
  `Kanji.jlptLevel` and `Kanji.grade` already on the model.
- **Search field**: matches kanji literal or any on/kun reading (kana).
- Filter + search are pure, testable predicate logic in `KanjiListFeature`
  (TDD): new state `filter` + `searchText`, derived `visibleKanji`. The view
  binds to these; the full `kanji` array load is unchanged.
- Empty result → cute `ContentUnavailableView` (pastel).

## 4. Language selector → Settings (設定)

- Remove the `globe` menu from the browse toolbar.
- 設定 tab gains a **言語 / Language** section (the same `AppLanguage` picker,
  driven by the existing `@AppStorage("appLanguage")`), above the reminder
  section. Both rendered as `RoundedCard` sections. No logic change — the
  binding source is identical, only its location moves.

## 5. Detail (漢字) restyle

- Header → **hero `RoundedCard`**: large kanji in a `PastelTile`, gloss in
  rounded title, grade/JLPT as `CandyChip`s.
- 読み / 画順 / 活用 / 例文 / 関連 each become a `RoundedCard` section with a
  small colored dot accent on the section header. Same content + order.
- Toolbar actions (復習に追加 / 書いて練習) keep behavior; styled to match.

## 6. Plan / Review / Settings + global

- 共通: cream-pink background, `RoundedCard` sections, candy-tone buttons,
  rounded font. Progress / today's-kanji / due-list rendered as pastel cards.
- `RootView`: `.tint(Palette.accent)` app-wide, tab bar + nav tinted, background
  unified. Tab icons kept (一覧/プラン/復習/設定).

## 7. Testing & verification

- **Browse filter/search**: unit tests first (TDD) in `KanjiListFeatureTests`
  — predicate by JLPT, by grade, by literal, by reading, combined with search,
  empty result.
- **Visual**: build + run on the iOS 26.5 simulator, screenshot each screen,
  iterate. (Pure view styling is not unit-tested.)
- Existing app tests must stay green; `ENABLE_DEBUG_DYLIB=NO` (already added for
  the iOS-27-device launch issue) stays.

## 8. Non-goals

New cards/quizzes, animations beyond existing stroke player, zh-Hant, theme
toggle, dark mode tuning. Keep scope to the redesign + browse filter/search +
language move.

# Study Card (Kanji Detail) — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: app scaffold + writing canvas + study plan (merged) and the full
enriched `kanji.sqlite` (readings, 4-language glosses, words, sentences, relations).

## 1. Purpose

Surface the gathered data: tapping a kanji opens a **study card** showing its
meaning (Korean 훈음), readings, usage words, and example sentences, with a
button into the existing writing canvas. Also re-bundles the full 2,136-kanji
enriched DB so the app ships real content.

## 2. Scope & Non-Goals

In scope:
- Re-bundle the enriched `kanji.sqlite` (2,136 kanji, all tables) into the app.
- `DictionaryClient` endpoints: `glosses`, `words`, `sentences` (+ GRDB live).
- A `KanjiDetail` module: `KanjiDetailFeature` + `KanjiDetailView`.
- Navigation restructure: tap → study card → (button) → writing canvas, via a
  `Destination` enum in the existing nav stacks.

Non-goals (follow-on):
- App language selector / full i18n string catalogs (v1 fixes display to Korean:
  ko 훈음 headline + ko sentence translation; word meanings shown in English,
  the only word-gloss language in the data).
- Displaying relations (antonym/related) — word-level, deferred.
- Korean word meanings; stroke-order animation; SRS.

## 3. Re-bundle

Copy `data-pipeline/out/kanji.sqlite` (the full enriched build) to
`app/Sources/DictionaryClient/Resources/kanji.sqlite`, replacing the
core+strokes placeholder. `allKanji`/`strokeOrder` are unchanged; the existing
`DictionaryClientTests` (count == 2136, 山 strokes) still pass.

## 4. DictionaryClient additions (interface + GRDB live)

```
var glosses:   @Sendable (_ kanjiID: Int) async throws -> [String: String]   // lang -> text
var words:     @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [WordEntry]
var sentences: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [ExampleSentence]
```
New `SharedModels` value types:
- `WordEntry { id: Int, surface: String, reading: String, meaningEn: String? }`
- `ExampleSentence { id: Int, textJa: String, translations: [String: String] }`

Live SQL:
- glosses: `SELECT lang, text FROM gloss WHERE kanji_id = ?` → dict (last wins;
  one row per lang).
- words: `SELECT w.id, w.surface, w.reading_kana, (one en gloss) FROM word w
  JOIN word_kanji wk ON wk.word_id=w.id WHERE wk.kanji_id=? ORDER BY w.is_common
  DESC, w.id LIMIT ?`.
- sentences: `SELECT s.id, s.text_ja FROM sentence s JOIN sentence_kanji sk …
  WHERE sk.kanji_id=? LIMIT ?`, then per-sentence translations
  `SELECT lang, text FROM sentence_translation WHERE sentence_id=?`.

## 5. KanjiDetail module

- **`KanjiDetailFeature`** (`@Reducer`) — State `{kanji: Kanji,
  glosses: [String:String], words: IdentifiedArrayOf<WordEntry>,
  sentences: [ExampleSentence], isLoading}`; Action `{onAppear, loaded(...),
  writeTapped}`. `onAppear` concurrently loads glosses/words/sentences; `loaded`
  fills state; `writeTapped` is handled by the parent (navigation).
- **`KanjiDetailView`** — scrolled sections:
  1. Header: large literal, Korean 훈음 (`glosses["ko"]`), grade/JLPT chips.
  2. 読み: 음독 (on) / 훈독 (kun) from the kanji's readings.
  3. 活用 (words): list of `surface · reading · meaningEn`.
  4. 例文 (sentences): each shows `textJa` + the `ko` translation.
  5. A "書いて練習" button sending `.writeTapped`.

`KanjiDetail` module deps: `{SharedModels, DictionaryClient, ComposableArchitecture}`.

## 6. Navigation restructure

Replace the stack element type (currently `KanjiWritingFeature.State`) with a
`Destination` `@Reducer` enum holding `.detail(KanjiDetailFeature.State)` and
`.writing(KanjiWritingFeature.State)`. In both `AppFeature` (browse stack) and
`RootFeature` (plan tab stack):
- a kanji tap appends `.detail(KanjiDetailFeature.State(kanji:))`;
- the parent intercepts `.path(.element(id:, .detail(.writeTapped)))` and
  appends `.writing(KanjiWritingFeature.State(kanji:))`.
The `NavigationStack` `destination:` closure switches on the `Destination` store
to render `KanjiDetailView` or `KanjiWritingView`. `AppFeature` module gains a
`KanjiDetail` dependency (it already depends on `WritingCanvas`).

## 7. Testing

- **DictionaryClient** (integration, bundled enriched DB): `glosses(山)` includes
  `ko == "메 산"`; `words(山, limit)` returns non-empty entries with surface/reading;
  `sentences(山, limit)` returns a sentence with a non-empty `textJa` and ≥1
  translation. Existing `allKanji` count == 2136 still holds.
- **`KanjiDetailFeature`** (`TestStore`, mocked client): `onAppear` → `loaded`
  populates glosses/words/sentences; `writeTapped` is a no-op in the child.
- **Navigation**: a parent-reducer test that `.detail(.writeTapped)` appends a
  `.writing` element to the stack.
- Build verification: `tuist generate` + `xcodebuild test` on an iOS 26 sim,
  green. Visual layout is manual QA.

## 8. Build order (this slice)

1. Re-bundle the enriched DB; update DictionaryClient integration tests to the
   richer-data invariants.
2. `SharedModels` `WordEntry` + `ExampleSentence`; `DictionaryClient`
   `glosses`/`words`/`sentences` interface + GRDB live (TDD integration).
3. `KanjiDetail` module: `KanjiDetailFeature` (TDD) + `KanjiDetailView`
   (build-verified).
4. Navigation `Destination` enum in `AppFeature`/`RootFeature` + views; tap →
   detail → write; full build/test green.

## 9. Follow-on (not in this slice)

App language selector + i18n; relations display; Korean word meanings;
stroke-order animation; promote native-gloss hard gate.

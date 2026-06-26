# Relations Display in Study Card — Design

Date: 2026-06-26
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Builds on: study-card slice (merged) + the `relation` data in the bundled DB.

## 1. Purpose

The DB has antonym/related word relations but the study card doesn't show them.
Surface, for a kanji, the antonym and related words of the words that contain it.

## 2. Scope & Non-Goals

In scope:
- `RelationEntry { surface, type }` in `SharedModels`.
- A `DictionaryClient.relations(forKanjiID:, limit:)` endpoint (+ GRDB live).
- `KanjiDetailFeature` loads relations; `KanjiDetailView` shows a 関連 section.

Non-goals (follow-on):
- Tapping a related word to navigate to it.
- Localizing the section/type labels (UI-string i18n is a separate follow-on).
- Showing the source word each relation came from.

## 3. Components

- **`RelationEntry`** (`SharedModels`): `struct RelationEntry: Equatable,
  Identifiable, Sendable { id: String (= "\(type):\(surface)"), surface, type }`.
  `type` is `"antonym"` or `"related"`.
- **`DictionaryClient.relations`**: `@Sendable (_ kanjiID: Int, _ limit: Int)
  async throws -> [RelationEntry]`. Live SQL joins the kanji's words to their
  relations and the related word's surface:
  ```sql
  SELECT DISTINCT r.type, wb.surface
  FROM word_kanji wk
  JOIN relation r ON r.word_id_a = wk.word_id
  JOIN word wb ON wb.id = r.word_id_b
  WHERE wk.kanji_id = ?
  ORDER BY r.type, wb.surface
  LIMIT ?
  ```
- **`KanjiDetailFeature`**: `State.relations: [RelationEntry]`; `onAppear` loads
  it concurrently with glosses/words/sentences; `loaded` carries it.
- **`KanjiDetailView`**: a 関連 section (shown only when non-empty) listing
  antonyms then related words as chips/text, grouped by `type`.

## 4. Testing

- **Integration** (bundled DB): `relations(forKanjiID:, limit:)` for a kanji with
  known relations returns non-empty `RelationEntry`s with a valid `type`.
- **`KanjiDetailFeature`** (`TestStore`): `onAppear` → `loaded` populates
  `relations` from the mocked client.
- Build verification green; layout is manual QA.

## 5. Build order

1. `RelationEntry` (`SharedModels`) + `relations` endpoint (interface + GRDB
   live) + integration test.
2. `KanjiDetailFeature` loads relations (extend State/Action/onAppear/loaded) +
   updated feature test.
3. `KanjiDetailView` 関連 section (build-verified).

## 6. Follow-on

Tap-through navigation to a related word; localized labels; show the bridging word.

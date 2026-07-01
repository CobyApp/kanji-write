# Kanji + Vocabulary App — Word Detail, Bidirectional Links, Wordbook — Design

Date: 2026-07-01
Status: Approved (user decisions: separate word-only FSRS review tab;
sentence↔word link built in the pipeline). Builds on: iPhone adaptive shell,
JLPT-only classification, FSRS kanji engine, multilingual sentence glosses.

## 1. Purpose

Grow the app from kanji-only into a **kanji + vocabulary** learner. Today words
appear as flat, non-tappable text under a kanji. The goal:

1. **Word detail** — tap a word anywhere → a screen with its reading, native
   meaning, example sentences, and the kanji it contains.
2. **Bidirectional navigation** — from a word, tap any kanji → that kanji's
   detail; from a kanji, tap any word → that word's detail. Drill back and forth
   to arbitrary depth.
3. **Wordbook (単語帳)** — save words, and study them with a **separate**
   word-only FSRS review (distinct from the kanji session).

## 2. Data model (pipeline)

The one missing edge is **sentence ↔ word**. Sentences currently link only to
kanji (`sentence_kanji`, built by scanning sentence chars for kanji literals).

New table `sentence_word(sentence_id, word_id, UNIQUE(sentence_id, word_id))`
with an index on `word_id`. No JA tokenizer is available (deps are `lxml` only),
and adding MeCab/fugashi is out of scope. Instead, a dependency-free precomputed
link built in `load_sentences`:

- Candidate words for a sentence = words that share ≥1 kanji with the sentence
  (intersect the sentence's linked kanji with `word_kanji`). This is cheap and
  cuts the search from 25k words to a handful.
- Link a candidate when its `surface` occurs as a substring of `text_ja`.
- Cap per word (mirroring `per_kanji_cap`) so a common word doesn't collect
  thousands of sentences; keep shortest sentences first (same ordering as today).

This is surface-match, not full morphology — acceptable and reversible; a
tokenizer-backed pass can replace it later without schema change.

## 3. App architecture

### 3.1 Navigation — StackState

Replace the single `@Presents detail` + `@Presents writing` with a TCA
`StackState<Path.State>` where

```
@Reducer enum Path { case kanji(KanjiDetailFeature); case word(WordDetailFeature); case writing(KanjiWritingFeature) }
```

Selecting a kanji (sidebar/list/search/session) resets the stack root to
`.kanji`. Words/kanji tapped inside a detail append to the stack, enabling
kanji→word→kanji→… to any depth. Both layouts render this one stack:

- **compact (iPhone)**: each tab's `NavigationStack(path:)` is the stack.
- **regular (iPad)**: the split view's detail column is a `NavigationStack(path:)`
  over the same state; picking a new kanji replaces the root.

`tabSelected` still clears the stack so it never leaks between compact tabs.

### 3.2 WordDetail

`WordDetailFeature` (mirrors `KanjiDetailFeature`): loads meaning (localized,
`wordMeaning` fallback), example sentences (`sentencesForWord`), and the kanji in
the word (`kanjiForWord`). `WordDetailView` shows the surface + reading header,
meaning, a row of tappable kanji tiles, an example-sentences section, and a
"単語帳に追加" / "復習に追加" action.

### 3.3 DictionaryClient additions

- `word(id) -> WordEntry?`
- `sentencesForWord(wordID, limit) -> [ExampleSentence]` (join `sentence_word`)
- `kanjiForWord(wordID) -> [Kanji]` (join `word_kanji`, full rows so a
  deep-pushed word detail is self-contained)

### 3.4 Kanji detail wiring

The 活用/words section rows become buttons that push `.word`. (Meaning display
and fallback are unchanged.)

## 4. Wordbook + word review

- **WordbookStore** (JSON file, like `ReviewStore`): the set of saved `word_id`s.
- **WordReviewStore**: FSRS `ReviewRecord`s for words. `ReviewRecord.kanjiID` is
  reused as a generic item id (a word's `id`) in a *separate* store file, so the
  kanji and word SRS never mix. (No change to `ReviewRecord`/`FSRS`.)
- **単語 review tab/section**: a word-only FSRS session (due saved words + new
  saved words), self-graded like the kanji hub. Saving a word seeds its initial
  FSRS record. Curriculum order for words = saved order (or JLPT of the word's
  hardest kanji — TBD in Phase 4).

IA: iPhone gains a 単語 tab (学習 / 単語 / 一覧 / 設定) or the 学習 hub gets a
漢字/単語 segmented switch — decided in Phase 4 build.

## 5. Phased plan

1. **Pipeline**: `sentence_word` table + link in `load_sentences` + `build_db`
   wiring + tests; rebuild & re-bundle `kanji.sqlite`.
2. **DictionaryClient**: `word`, `sentencesForWord`, `kanjiForWord` + live SQL +
   tests.
3. **Navigation refactor + WordDetail + bidirectional links**: `StackState`
   `Path`, `WordDetailFeature`/`View`, tappable words (kanji detail) and kanji
   chips (word detail); both layouts. TCA `TestStore` coverage for push flows.
4. **Wordbook + word FSRS**: `WordbookStore` + `WordReviewStore` + save UI +
   単語 review surface + tests.

Each phase builds and ships independently (green build + tests) before the next.

## 6. Testing

- Pipeline: `sentence_word` linking (shares-kanji + substring; cap; no self-noise
  on words with no shared kanji) via fixtures.
- DictionaryClient: integration reads against the bundled DB.
- Features: `TestStore` for word/kanji push flows, wordbook add/remove, word
  FSRS grading. Pure helpers (`wordMeaning`, curriculum) unit-tested.

## 7. Non-goals (v1)

Per-sense word glosses; conjugation tables; audio for words; sharing the kanji
and word SRS into one queue; tokenizer-based sentence segmentation.

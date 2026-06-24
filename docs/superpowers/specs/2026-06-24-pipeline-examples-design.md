# Data Pipeline — Example Sentences (Tatoeba) — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: core, stroke-order, vocabulary slices (merged)

## 1. Purpose

Add **example sentences** to the pipeline: for each jōyō kanji, a few Japanese
sentences that contain it, each with translations (English / Korean / Chinese).
This is the data behind the study card's "例文 / example" section. Follow-on
plan #3 from the parent design.

## 2. Scope & Non-Goals

In scope:
- `sentence`, `sentence_translation`, `sentence_kanji` tables.
- A Tatoeba ingester producing Japanese sentences + en/ko/zh translations.
- A loader that attaches a capped number (default 3) of the shortest sentences
  to each jōyō kanji they contain.
- Orchestrator integration + an informational (non-gating) report field.
- Fixtures + a fetch step for the real Tatoeba dumps.

Non-goals (follow-on):
- Word-level (rather than kanji-level) sentence matching.
- Difficulty / quality ranking beyond "shortest first".
- Audio, furigana alignment.
- The study-card UI that displays sentences (separate app slice).

## 3. Data source

- **Tatoeba** (CC BY 2.0 FR). `sentences.csv` (TSV: `id`, `lang`, `text`) and
  `links.csv` (TSV: `sentence_id`, `translation_id`). Language codes:
  `jpn`, `eng`, `kor`, `cmn` (Mandarin). Links in the dump are bidirectional but
  the ingester treats them as undirected to be safe. Attribution added to
  `fetch_sources.sh`.

## 4. Schema change (additive)

```sql
CREATE TABLE sentence (
    id      INTEGER PRIMARY KEY,
    text_ja TEXT NOT NULL
);
CREATE TABLE sentence_translation (
    id          INTEGER PRIMARY KEY,
    sentence_id INTEGER NOT NULL REFERENCES sentence(id),
    lang        TEXT NOT NULL,   -- 'en' | 'ko' | 'zh'
    text        TEXT NOT NULL
);
CREATE TABLE sentence_kanji (
    sentence_id INTEGER NOT NULL REFERENCES sentence(id),
    kanji_id    INTEGER NOT NULL REFERENCES kanji(id),
    UNIQUE(sentence_id, kanji_id)
);
CREATE INDEX idx_sentence_translation_sentence ON sentence_translation(sentence_id);
CREATE INDEX idx_sentence_kanji_kanji ON sentence_kanji(kanji_id);
```

Purely additive; existing tables and gates unchanged.

## 5. Components (each one responsibility)

- **`ingest/tatoeba.py`** — `parse_tatoeba(sentences_path, links_path) -> list[Sentence]`,
  where `Sentence` is a dataclass `{ja_text: str, translations: dict[str, str]}`
  (keys among `en`/`ko`/`zh`). Steps: (1) read `sentences.csv`, keeping only rows
  whose lang is `jpn`/`eng`/`kor`/`cmn` into `{id: (lang, text)}`; (2) read
  `links.csv` into an undirected adjacency `{id: set(ids)}`; (3) for each `jpn`
  sentence, collect one translation per target lang from its neighbours
  (`eng→en`, `kor→ko`, `cmn→zh`); keep the sentence only if it has ≥1
  translation. Pure parsing, no DB.
- **`loader.py`** (extend) — `load_sentences(conn, sentences, per_kanji_cap=3)`:
  sort sentences by `len(ja_text)` ascending; build a `literal→kanji_id` map and
  a per-kanji counter; for each sentence, find the jōyō kanji in `ja_text` whose
  counter is `< per_kanji_cap`; if any, insert the `sentence` once + its
  `sentence_translation` rows, link it to those kanji via `sentence_kanji`, and
  bump their counters. Sentences needed by no under-cap kanji are skipped.
- **`build_db.py`** (extend) — `build(...)` gains `sentences_path` and
  `links_path`; after `load_words`, it calls `parse_tatoeba` + `load_sentences`.
- **`validate.py`** (extend) — `coverage_report` gains `kanji_without_sentences`
  (informational). The build does **not** gate on it.

## 6. Data flow

`… load_words → parse_tatoeba → load_sentences(cap=3) → assert_core_gates → emit`.
Sentence→kanji links come from scanning each sentence for jōyō-kanji characters,
capped per kanji and biased toward short sentences.

## 7. Testing

- **`parse_tatoeba`**: fixtures — `sentences.csv` with `1 jpn 山が高い。`,
  `2 eng The mountain is high.`, `3 kor 산이 높다.`, `6 cmn 这是山。`,
  `4 jpn 学校に行く。`, `5 eng I go to school.`, `7 fra ...`; `links.csv`
  pairing 1↔2,1↔3,1↔6,4↔5. Assert sentence 1 → `{en,ko,zh}`, sentence 4 → `{en}`,
  the French sentence is ignored, and a jpn sentence with no translation is
  dropped.
- **`load_sentences`**: seed 山/学 kanji; cap=1; load 3 sentences containing 山
  of differing lengths → assert only the shortest is linked to 山 (cap honored),
  translations stored, sentence inserted once.
- **report**: `coverage_report` returns `kanji_without_sentences`;
  `assert_core_gates` does not raise on it.
- **integration** (`build_db`): build over all fixtures (kanjidic2, jlpt,
  kanjivg, jmdict, tatoeba sentences+links); assert 山 has a linked sentence and
  it has an English translation.

## 8. Build order (this slice)

1. `sentence`/`sentence_translation`/`sentence_kanji` schema + `Sentence` model +
   Tatoeba fixtures.
2. `parse_tatoeba` ingester (TDD).
3. `load_sentences` loader with per-kanji cap (TDD).
4. `kanji_without_sentences` report field (TDD, non-gating).
5. `build_db` integration (`sentences_path`, `links_path`) + fetch step (TDD).

Gets its own implementation plan. Follow-on: WordNet relations, Korean 훈, LLM
4-language glosses, study-card UI.

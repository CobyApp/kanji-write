# Data Pipeline — Vocabulary (JMdict) — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: data-pipeline core + stroke-order slices (merged)

## 1. Purpose

Add **vocabulary** to the pipeline: for each jōyō kanji, the common words that
contain it (surface, kana reading, English gloss). This is the data behind the
study card's "usage / 活用" section. Follow-on plan #2 from the parent design.

## 2. Scope & Non-Goals

In scope:
- `word`, `word_kanji`, `word_gloss` tables.
- A JMdict ingester producing common words (with a kanji form) + English glosses.
- A loader linking each word to the jōyō kanji whose literal appears in its
  surface.
- Orchestrator integration + an informational coverage report field.
- Fixtures so the build passes offline + a fetch step for the real JMdict.

Non-goals (follow-on):
- Native ko/ja/zh word meanings (JMdict is English; multilingual word glosses
  come later, possibly via the LLM slice).
- Precise frequency ranking beyond a common/not-common flag.
- Per-sense detail (part of speech, multiple senses) — v1 keeps up to 3 English
  glosses on the entry's first sense set.
- The study-card UI that displays these words (separate app slice).

## 3. Data source

- **JMdict** (EDRDG, CC BY-SA 4.0). Each `<entry>` has kanji forms (`<k_ele><keb>`),
  readings (`<r_ele><reb>`), and senses (`<sense><gloss>`). Priority tags
  (`<ke_pri>`/`<re_pri>`: `news1`, `ichi1`, `spec1`, `gai1`, `nfXX`, …) mark
  common entries. The English edition's `<gloss>` carries English text (no
  `xml:lang`, or `xml:lang="eng"`). Attribution added to `fetch_sources.sh`.

## 4. Schema change (additive)

```sql
CREATE TABLE word (
    id           INTEGER PRIMARY KEY,
    surface      TEXT NOT NULL,
    reading_kana TEXT NOT NULL,
    is_common    INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE word_kanji (
    word_id  INTEGER NOT NULL REFERENCES word(id),
    kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    UNIQUE(word_id, kanji_id)
);
CREATE TABLE word_gloss (
    id      INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL REFERENCES word(id),
    lang    TEXT NOT NULL,   -- 'en' in v1
    text    TEXT NOT NULL
);
CREATE INDEX idx_word_kanji_kanji ON word_kanji(kanji_id);
CREATE INDEX idx_word_gloss_word ON word_gloss(word_id);
```

Purely additive; existing tables and gates unchanged.

## 5. Components (each one responsibility)

- **`ingest/jmdict.py`** — `parse_jmdict(path) -> list[Word]`, where `Word` is a
  dataclass `{surface: str, reading_kana: str, is_common: bool,
  en_glosses: list[str]}`. Rules: keep only entries that **have a kanji form
  (`keb`) and at least one priority tag** (common). `surface` = first `keb`;
  `reading_kana` = first `reb`; `en_glosses` = up to 3 English glosses from the
  entry's senses. Pure parsing, no DB.
- **`loader.py`** (extend) — `load_words(conn, words)`: builds a
  `literal -> kanji_id` map from the `kanji` table; for each word, inserts a
  `word` row + its `word_gloss` rows, then for each distinct character in
  `surface` that is a jōyō kanji, inserts a `word_kanji` link. Words whose
  surface contains no jōyō kanji are still stored but simply have no links.
- **`build_db.py`** (extend) — `build(...)` gains a `jmdict_path` parameter;
  after `load_kanji`/`load_stroke_order`, it calls `parse_jmdict` + `load_words`.
- **`validate.py`** (extend) — `coverage_report` gains `kanji_without_words`
  (informational count). The build does **not** fail on it — not every jōyō
  kanji has a common JMdict word, and vocabulary is supplementary.

## 6. Data flow

`… load_kanji → load_stroke_order → parse_jmdict → load_words →`
`assert_core_gates → emit`. Word→kanji links are resolved by scanning each
word's surface for jōyō-kanji characters (JMdict and KANJIDIC2 share Unicode).

## 7. Testing

- **`parse_jmdict`**: fixture with 山 (mountain/hill, common), 学校 (school,
  common), 山岳 (no priority → dropped), and a kana-only entry (no keb →
  dropped). Assert exactly the two common entries with correct surface/reading/
  glosses; assert gloss cap at 3.
- **`load_words`**: seed 山/学 kanji rows; load the parsed words; assert 学校
  links to 学 (校 is absent from the seeded set, so no link to it), 山 links to
  山, glosses are stored, and a word with no jōyō kanji creates no links.
- **gate/report**: `coverage_report` returns a `kanji_without_words` count and
  `assert_core_gates` does NOT raise on it.
- **integration** (`build_db`): build over the four fixtures (kanjidic2, jlpt,
  kanjivg, jmdict); assert 山 has a linked word whose surface is 山.

## 8. Build order (this slice)

1. `word`/`word_kanji`/`word_gloss` schema + JMdict fixture.
2. `parse_jmdict` ingester (TDD).
3. `load_words` loader (TDD).
4. `kanji_without_words` report field (TDD, non-gating).
5. `build_db` integration (`jmdict_path`) + fetch step (TDD integration).

Gets its own implementation plan. Follow-on data plans: Tatoeba sentences,
WordNet relations, Korean 훈, LLM 4-language glosses.

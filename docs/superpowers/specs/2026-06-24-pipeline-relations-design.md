# Data Pipeline — Word Relations (JMdict antonym / related) — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: core, stroke-order, vocabulary, examples slices (merged)

## 1. Purpose

Add **word-level relations** — antonyms and related words — so the study card
can show 反意語 / 関連語. Follow-on plan #4 (relations portion) from the parent
design. Uses the JMdict file already fetched (no new download).

## 2. Scope & Non-Goals

In scope:
- A `relation` table (word↔word, typed).
- A JMdict relations ingester reading `<ant>` (antonym) and `<xref>` (related)
  from senses.
- A loader linking relations only between words already stored (common words).
- Orchestrator integration (reusing the existing `jmdict_path`).
- Fixtures + tests.

Non-goals (follow-on):
- True synonyms from Japanese WordNet synsets (JMdict has no clean synonym
  relation; `<xref>` is "see also" / related, stored as such).
- Relation symmetrization / dedup of inverse pairs.
- Relations whose target is not a stored common word (skipped).
- The study-card UI that displays relations.

## 3. Data source

- **JMdict** (already at `sources/jmdict.xml`). Within `<sense>`:
  - `<ant>` — antonym; text is the target's kanji/reading form, possibly
    `語・よみ・senseNo` (parts joined by `・`).
  - `<xref>` — cross-reference ("see also"); same text format. Stored as a
    `related` relation, not a true synonym.

## 4. Schema change (additive)

```sql
CREATE TABLE relation (
    id        INTEGER PRIMARY KEY,
    word_id_a INTEGER NOT NULL REFERENCES word(id),
    word_id_b INTEGER NOT NULL REFERENCES word(id),
    type      TEXT NOT NULL,   -- 'antonym' | 'related'
    UNIQUE(word_id_a, word_id_b, type)
);
CREATE INDEX idx_relation_a ON relation(word_id_a);
```

Purely additive; existing tables and gates unchanged.

## 5. Components (each one responsibility)

- **`ingest/jmdict_relations.py`** — `parse_jmdict_relations(path) -> list[Relation]`,
  where `Relation` is a dataclass `{source_surface: str, target_surface: str,
  type: str}`. For each entry with a kanji form: `source_surface` = first `keb`;
  for each `<sense>`, each `<ant>` yields a `'antonym'` relation and each
  `<xref>` a `'related'` relation; the target surface is the text **before the
  first `・`** (dropping the reading/sense-number parts). Streams with
  `iterparse` like the word parser. Pure parsing, no DB.
- **`loader.py`** (extend) — `load_relations(conn, relations)`: build a
  `surface → word_id` map from the `word` table (first id wins on duplicate
  surfaces); for each relation, resolve both `source_surface` and
  `target_surface`; insert a `relation` row only when **both resolve** to stored
  words and `a != b`. `INSERT OR IGNORE` honours the UNIQUE constraint.
- **`build_db.py`** (extend) — after `load_words`, call
  `parse_jmdict_relations(jmdict_path)` + `load_relations`. **No new path
  parameter** — relations come from the same JMdict file.
- **`validate.py`** — **unchanged**. Relations are word-level and supplementary;
  they do not map to a per-kanji coverage gate.

## 6. Data flow

`… load_words → parse_jmdict_relations(jmdict_path) → load_relations → emit`.
A relation is materialized only when both endpoints are stored common words.

## 7. Testing

- **`parse_jmdict_relations`**: fixture entries carrying `<ant>` and `<xref>`
  (including a target in `語・よみ・1` form) → assert the relation list has the
  right `(source, target, type)` tuples and that the `・`-suffix is stripped.
- **`load_relations`**: seed `word` rows for two surfaces; a relation between
  them inserts (type preserved); a relation whose target is not stored is
  skipped; a duplicate relation does not double-insert.
- **integration** (`build_db`): the existing `jmdict_sample.xml` gains an
  `<ant>`/`<xref>` between its two common words (山, 学校); after build, assert a
  `relation` row links them with the expected type.

## 8. Build order (this slice)

1. `relation` schema + `Relation` model + JMdict `<ant>`/`<xref>` added to the
   existing `jmdict_sample.xml` fixture.
2. `parse_jmdict_relations` ingester (TDD).
3. `load_relations` loader (TDD).
4. `build_db` integration (reuse `jmdict_path`) + integration assertion (TDD).

Gets its own implementation plan. Follow-on: WordNet true synonyms, Korean 훈,
LLM 4-language glosses, study-card UI.

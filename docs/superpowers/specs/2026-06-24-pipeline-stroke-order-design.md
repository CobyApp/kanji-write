# Data Pipeline — Stroke Order (KanjiVG) — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: `docs/superpowers/plans/2026-06-23-data-pipeline-core.md` (core slice, merged)

## 1. Purpose

Add **stroke-order data (KanjiVG)** to the data pipeline so the bundled
`kanji.sqlite` carries, for each kanji, its strokes in writing order. This is the
data the app's writing canvas needs to draw guide strokes and animate stroke
order. It is follow-on plan #1 from the parent design.

## 2. Scope & Non-Goals

In scope:
- A `stroke_order` table: one row per stroke, ordered, holding the SVG path data.
- A KanjiVG XML ingester producing `codepoint → [path "d" strings in stroke order]`.
- A loader that links strokes to existing `kanji` rows by codepoint.
- Orchestrator integration + a coverage gate (every loaded kanji has ≥1 stroke).
- Fixtures (山, 学) so the build + gate pass offline; a `fetch` step for the real
  KanjiVG release.

Non-goals:
- Stroke-order *checking* / handwriting recognition (app concern, later).
- Per-stroke metadata beyond the path `d` and its order (KanjiVG's `kvg:type`,
  radical grouping, median points) — not needed to draw/animate v1.
- Rendering. The pipeline only stores data; the app renders it.

## 3. Data source

- **KanjiVG** (CC BY-SA 3.0). The aggregated release file (`kanjivg-*.xml`)
  contains `<kanji id="kvg:kanji_<hex>">` elements; each wraps `<g>`/`<path>`
  descendants. The document order of `<path>` elements **is** the stroke order;
  each `<path>`'s `d` attribute is the stroke geometry. The codepoint is the hex
  in the `id` (`kvg:kanji_05c71` → `0x5C71` = 山).
- Attribution already noted in `fetch_sources.sh` / the planned app attributions
  screen; KanjiVG line added there.

## 4. Schema change (additive)

Add to `kanjipipe/schema.py` DDL:

```sql
CREATE TABLE stroke_order (
    id        INTEGER PRIMARY KEY,
    kanji_id  INTEGER NOT NULL REFERENCES kanji(id),
    ordinal   INTEGER NOT NULL,   -- 1-based stroke order
    path_d    TEXT    NOT NULL,   -- SVG path "d" attribute for this stroke
    UNIQUE(kanji_id, ordinal)
);
CREATE INDEX idx_stroke_order_kanji ON stroke_order(kanji_id);
```

One row per stroke keeps it queryable and lets the app fetch strokes in order
(`ORDER BY ordinal`) without parsing a blob. Purely additive — the core slice's
tables and gates are unchanged.

## 5. Components (each one responsibility)

- **`ingest/kanjivg.py`** — `parse_kanjivg(path) -> dict[int, list[str]]`: maps
  codepoint → ordered list of stroke `d` strings. Pure parsing, no DB.
- **`loader.py`** (extend) — `load_stroke_order(conn, strokes_by_codepoint)`:
  for each existing `kanji` row, look up its strokes by codepoint and insert
  `stroke_order` rows (ordinal = 1-based index). Kanji absent from the map are
  left without strokes (the gate decides if that fails the build).
- **`validate.py`** (extend) — `coverage_report` gains `missing_stroke_order`
  (kanji with zero stroke rows); `assert_core_gates` fails if any loaded kanji
  has no strokes.
- **`build_db.py`** (extend) — `build(...)` gains a `kanjivg_path` parameter;
  after `load_kanji`, it calls `parse_kanjivg` + `load_stroke_order`, then the
  (now stricter) gate.
- **`scripts/fetch_sources.sh`** (extend) — fetch the KanjiVG release into
  `sources/`.

## 6. Data flow

`parse_kanjidic2 → filter_joyo → merge_jlpt → init_db → load_kanji →`
`parse_kanjivg → load_stroke_order → assert_core_gates → emit`.

Strokes link to kanji **by codepoint** (KanjiVG and KANJIDIC2 share Unicode
scalars). The loader queries `SELECT id, codepoint FROM kanji` and matches.

## 7. Testing

- **`parse_kanjivg`**: fixture with 山 (3 strokes) + 学 (8 strokes); assert
  codepoint keys, stroke counts, and that path order matches document order;
  assert a kanji with no `<path>` yields an empty list (or is absent).
- **`load_stroke_order`**: in-memory DB seeded with 山/学 kanji rows; load a
  stroke map; assert `stroke_order` rows exist with correct `ordinal` order and
  `path_d`, and that FK links resolve.
- **gate**: a kanji with no strokes makes `assert_core_gates` raise
  `"missing stroke order"`.
- **integration** (`build_db`): build over the kanjidic2 + jlpt + kanjivg
  fixtures; assert the emitted DB has 山 with 3 ordered strokes and 学 with 8.

## 8. Build order (this slice)

1. `stroke_order` schema + KanjiVG fixture.
2. `parse_kanjivg` ingester (TDD).
3. `load_stroke_order` loader (TDD).
4. `missing_stroke_order` gate (TDD).
5. `build_db` integration + `kanjivg_path` param + fetch script (TDD integration).

Gets its own implementation plan (this spec → plan → build). Follow-on data
plans (JMdict words, Tatoeba sentences, WordNet relations, Korean 훈, LLM
4-language glosses) remain separate.

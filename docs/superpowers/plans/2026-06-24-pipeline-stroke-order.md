# Data Pipeline — Stroke Order (KanjiVG) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the data pipeline so the bundled `kanji.sqlite` carries each kanji's strokes in writing order (from KanjiVG), gated so every loaded kanji has stroke data.

**Architecture:** Add a `stroke_order` table (one row per stroke). A new `parse_kanjivg` ingester maps codepoint → ordered stroke `d` strings; `load_stroke_order` links them to existing `kanji` rows by codepoint; the gate fails if any kanji lacks strokes; the orchestrator gains a `kanjivg_path` stage between `load_kanji` and the gate. Additive — the core slice is unchanged.

**Tech Stack:** Python 3.11+, lxml, sqlite3, pytest. All commands run from the repo root unless noted; use the existing venv at `data-pipeline/.venv`.

---

## File Structure (this slice)

```
data-pipeline/
├── kanjipipe/
│   ├── schema.py             # + stroke_order table (modify)
│   ├── ingest/kanjivg.py     # parse_kanjivg() (new)
│   ├── loader.py             # + load_stroke_order() (modify)
│   ├── validate.py           # + missing_stroke_order gate (modify)
│   └── build_db.py           # + kanjivg_path stage (modify)
├── scripts/fetch_sources.sh  # + KanjiVG fetch (modify)
└── tests/
    ├── fixtures/kanjivg_sample.xml   # 山 (3 strokes), 学 (8 strokes) (new)
    ├── test_kanjivg.py               # (new)
    ├── test_loader.py                # + stroke-order cases (modify)
    ├── test_validate.py              # + gate case (modify)
    ├── test_db.py                    # + table-exists case (modify)
    └── test_build_db.py              # update build() call + assert strokes (modify)
```

---

## Task 1: stroke_order schema + KanjiVG fixture

**Files:**
- Modify: `data-pipeline/kanjipipe/schema.py`
- Modify: `data-pipeline/tests/test_db.py`
- Create: `data-pipeline/tests/fixtures/kanjivg_sample.xml`

- [ ] **Step 1: Add a failing table-exists test**

In `data-pipeline/tests/test_db.py`, change the table-set assertion in
`test_init_db_creates_core_tables` to also require `stroke_order`:

```python
    assert {"kanji", "reading", "gloss", "stroke_order"} <= tables
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: FAIL — `stroke_order` not in the created tables.

- [ ] **Step 3: Add the table to the schema**

In `data-pipeline/kanjipipe/schema.py`, append to the `DDL` string (after the
`gloss` table and its index, before the closing `"""`):

```sql
CREATE TABLE stroke_order (
    id        INTEGER PRIMARY KEY,
    kanji_id  INTEGER NOT NULL REFERENCES kanji(id),
    ordinal   INTEGER NOT NULL,
    path_d    TEXT    NOT NULL,
    UNIQUE(kanji_id, ordinal)
);

CREATE INDEX idx_stroke_order_kanji ON stroke_order(kanji_id);
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: PASS.

- [ ] **Step 5: Create the KanjiVG fixture**

Create `data-pipeline/tests/fixtures/kanjivg_sample.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kanjivg xmlns:kvg="http://kanjivg.tagaini.net">
  <kanji id="kvg:kanji_05c71">
    <g kvg:element="山">
      <path id="kvg:05c71-s1" d="M21,30 L21,70"/>
      <path id="kvg:05c71-s2" d="M50,20 L50,80"/>
      <path id="kvg:05c71-s3" d="M79,30 L79,70"/>
    </g>
  </kanji>
  <kanji id="kvg:kanji_05b66">
    <g kvg:element="学">
      <path id="kvg:05b66-s1" d="M1 1"/>
      <path id="kvg:05b66-s2" d="M2 2"/>
      <path id="kvg:05b66-s3" d="M3 3"/>
      <path id="kvg:05b66-s4" d="M4 4"/>
      <path id="kvg:05b66-s5" d="M5 5"/>
      <path id="kvg:05b66-s6" d="M6 6"/>
      <path id="kvg:05b66-s7" d="M7 7"/>
      <path id="kvg:05b66-s8" d="M8 8"/>
    </g>
  </kanji>
</kanjivg>
```

山 = U+5C71 (3 strokes), 学 = U+5B66 (8 strokes) — matching the jōyō kanji in
`kanjidic2_sample.xml`.

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/schema.py data-pipeline/tests/test_db.py data-pipeline/tests/fixtures/kanjivg_sample.xml
git commit -m "feat(data-pipeline): stroke_order table + KanjiVG fixture"
```

---

## Task 2: KanjiVG parser

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/kanjivg.py`
- Create: `data-pipeline/tests/test_kanjivg.py`

- [ ] **Step 1: Write the failing test**

Create `data-pipeline/tests/test_kanjivg.py`:

```python
# tests/test_kanjivg.py
from pathlib import Path

from kanjipipe.ingest.kanjivg import parse_kanjivg

FIXTURE = Path(__file__).parent / "fixtures" / "kanjivg_sample.xml"


def test_maps_codepoints_to_ordered_strokes():
    strokes = parse_kanjivg(FIXTURE)
    assert set(strokes) == {0x5C71, 0x5B66}
    assert len(strokes[0x5C71]) == 3
    assert len(strokes[0x5B66]) == 8


def test_preserves_document_order_as_stroke_order():
    strokes = parse_kanjivg(FIXTURE)
    assert strokes[0x5C71] == ["M21,30 L21,70", "M50,20 L50,80", "M79,30 L79,70"]


def test_kanji_without_paths_yields_empty_list(tmp_path):
    p = tmp_path / "k.xml"
    p.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<kanjivg><kanji id="kvg:kanji_05c71"><g></g></kanji></kanjivg>',
        encoding="utf-8")
    assert parse_kanjivg(p) == {0x5C71: []}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_kanjivg.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'kanjipipe.ingest.kanjivg'`.

- [ ] **Step 3: Write the parser**

Create `data-pipeline/kanjipipe/ingest/kanjivg.py`:

```python
"""Parse a KanjiVG XML file into a map of codepoint -> ordered stroke paths."""
import re
from pathlib import Path

from lxml import etree

# Top-level <kanji id="kvg:kanji_05c71"> carries the codepoint as hex.
_ID_RE = re.compile(r"kanji_([0-9a-fA-F]+)")


def _localname(el) -> str:
    return etree.QName(el.tag).localname if isinstance(el.tag, str) else ""


def _codepoint_from_id(kanji_id: str | None) -> int | None:
    if not kanji_id:
        return None
    match = _ID_RE.search(kanji_id)
    return int(match.group(1), 16) if match else None


def parse_kanjivg(path: str | Path) -> dict[int, list[str]]:
    root = etree.parse(str(path)).getroot()
    result: dict[int, list[str]] = {}
    for kanji in root.iter():
        if _localname(kanji) != "kanji":
            continue
        codepoint = _codepoint_from_id(kanji.get("id"))
        if codepoint is None:
            continue
        paths: list[str] = []
        for el in kanji.iter():
            if _localname(el) == "path":
                d = el.get("d")
                if d:
                    paths.append(d)
        result[codepoint] = paths
    return result
```

> Stroke order = document order of `<path>` elements (KanjiVG's invariant).
> Parsing is by element local-name so the `kvg:` namespace is irrelevant; `id`
> and `d` are un-namespaced attributes.

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_kanjivg.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/ingest/kanjivg.py data-pipeline/tests/test_kanjivg.py
git commit -m "feat(data-pipeline): KanjiVG parser (codepoint -> ordered stroke paths)"
```

---

## Task 3: load_stroke_order

**Files:**
- Modify: `data-pipeline/kanjipipe/loader.py`
- Modify: `data-pipeline/tests/test_loader.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_loader.py`:

```python
from kanjipipe.loader import load_stroke_order


def test_load_stroke_order_links_by_codepoint_in_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山, codepoint 0x5C71

    load_stroke_order(conn, {0x5C71: ["d1", "d2", "d3"]})

    rows = conn.execute(
        "SELECT ordinal, path_d FROM stroke_order so "
        "JOIN kanji k ON so.kanji_id = k.id WHERE k.literal = '山' "
        "ORDER BY ordinal").fetchall()
    assert rows == [(1, "d1"), (2, "d2"), (3, "d3")]


def test_load_stroke_order_skips_kanji_absent_from_map():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_stroke_order(conn, {})  # no strokes provided
    count = conn.execute("SELECT COUNT(*) FROM stroke_order").fetchone()[0]
    assert count == 0
```

(`_yama()` already exists in this test file and has `codepoint=0x5C71`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: FAIL — `cannot import name 'load_stroke_order'`.

- [ ] **Step 3: Implement the loader**

Append to `data-pipeline/kanjipipe/loader.py`:

```python
def load_stroke_order(
    conn: sqlite3.Connection,
    strokes_by_codepoint: dict[int, list[str]],
) -> None:
    rows = conn.execute("SELECT id, codepoint FROM kanji").fetchall()
    for kanji_id, codepoint in rows:
        for ordinal, path_d in enumerate(strokes_by_codepoint.get(codepoint, []), start=1):
            conn.execute(
                "INSERT INTO stroke_order (kanji_id, ordinal, path_d) "
                "VALUES (?, ?, ?)",
                (kanji_id, ordinal, path_d),
            )
    conn.commit()
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/loader.py data-pipeline/tests/test_loader.py
git commit -m "feat(data-pipeline): load_stroke_order links strokes to kanji by codepoint"
```

---

## Task 4: stroke-order coverage gate

**Files:**
- Modify: `data-pipeline/kanjipipe/validate.py`
- Modify: `data-pipeline/tests/test_validate.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_validate.py` (it already imports
`load_stroke_order`? add the import) — add at the top with the other imports:

```python
from kanjipipe.loader import load_kanji, load_stroke_order
```

(replace the existing `from kanjipipe.loader import load_kanji` line), then append:

```python
def test_assert_core_gates_fails_when_stroke_order_missing():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])          # has reading + EN gloss + grade, but no strokes
    with pytest.raises(ValueError, match="missing stroke order"):
        assert_core_gates(conn)


def test_assert_core_gates_passes_with_stroke_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])          # _good() is 山, codepoint 0x5C71
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert assert_core_gates(conn)["missing_stroke_order"] == 0
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: FAIL — `coverage_report` has no `missing_stroke_order` key / gate does not raise.

- [ ] **Step 3: Extend the report and gate**

In `data-pipeline/kanjipipe/validate.py`, add to the dict returned by
`coverage_report` (after `missing_grade`):

```python
        "missing_stroke_order": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM stroke_order s WHERE s.kanji_id = k.id)"),
```

And in `assert_core_gates`, add (after the `missing_grade` check):

```python
    if report["missing_stroke_order"]:
        problems.append(
            f"{report['missing_stroke_order']} kanji missing stroke order")
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: PASS. (The existing `_good()`-based gate tests still pass because they
now also need strokes only where the new tests add them — verify the older
`test_assert_core_gates_passes_on_complete_data` still passes; if it now fails
because `_good()` has no strokes, that test must seed strokes too. See Step 5.)

- [ ] **Step 5: Fix any now-failing pre-existing gate test**

The pre-existing `test_assert_core_gates_passes_on_complete_data` and
`test_assert_core_gates_fails_*` tests load `_good()` without strokes. With the
new gate, "passes on complete data" must now include strokes. Update ONLY
`test_assert_core_gates_passes_on_complete_data` to seed a stroke:

```python
def test_assert_core_gates_passes_on_complete_data():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert assert_core_gates(conn)["total"] == 1
```

The `fails_when_*` tests still correctly raise (they're missing some field), so
leave them unchanged. Re-run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/validate.py data-pipeline/tests/test_validate.py
git commit -m "feat(data-pipeline): gate fails when a kanji lacks stroke order"
```

---

## Task 5: orchestrator integration + fetch

**Files:**
- Modify: `data-pipeline/kanjipipe/build_db.py`
- Modify: `data-pipeline/tests/test_build_db.py`
- Modify: `data-pipeline/scripts/fetch_sources.sh`

- [ ] **Step 1: Update the integration test (failing)**

Overwrite `data-pipeline/tests/test_build_db.py`:

```python
# tests/test_build_db.py
from pathlib import Path

from kanjipipe.build_db import build

FIX = Path(__file__).parent / "fixtures"


def test_build_produces_sqlite_with_strokes(tmp_path):
    out = tmp_path / "kanji.sqlite"
    report = build(
        kanjidic2_path=FIX / "kanjidic2_sample.xml",
        jlpt_path=FIX / "jlpt_sample.json",
        kanjivg_path=FIX / "kanjivg_sample.xml",
        out_path=str(out),
    )
    assert out.exists()
    assert report["total"] == 2          # 山, 学 — 龠 filtered out
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0
    assert report["missing_stroke_order"] == 0

    import sqlite3
    with sqlite3.connect(out) as conn:
        literals = {r[0] for r in conn.execute("SELECT literal FROM kanji")}
        assert literals == {"山", "学"}
        yama_strokes = conn.execute(
            "SELECT so.path_d FROM stroke_order so JOIN kanji k ON so.kanji_id = k.id "
            "WHERE k.literal = '山' ORDER BY so.ordinal").fetchall()
        assert [r[0] for r in yama_strokes] == ["M21,30 L21,70", "M50,20 L50,80", "M79,30 L79,70"]
        gaku_count = conn.execute(
            "SELECT COUNT(*) FROM stroke_order so JOIN kanji k ON so.kanji_id = k.id "
            "WHERE k.literal = '学'").fetchone()[0]
        assert gaku_count == 8
    conn.close()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: FAIL — `build()` got an unexpected keyword argument `kanjivg_path`.

- [ ] **Step 3: Wire KanjiVG into the orchestrator**

In `data-pipeline/kanjipipe/build_db.py`:

(a) add the import at the top with the other ingest imports:
```python
from kanjipipe.ingest.kanjivg import parse_kanjivg
```
and extend the loader import:
```python
from kanjipipe.loader import load_kanji, load_stroke_order
```

(b) replace the `build` function with:
```python
def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    out_path: str,
) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)
    strokes = parse_kanjivg(kanjivg_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    try:
        load_kanji(conn, kanji)
        load_stroke_order(conn, strokes)
        report = assert_core_gates(conn)  # raises if a gate fails
    finally:
        conn.close()  # always release the handle, even on gate failure
    return report
```

(c) update `main()` to accept and pass `--kanjivg`:
```python
    parser.add_argument("--kanjivg", default="sources/kanjivg.xml")
```
(add this alongside the other `add_argument` calls), and change the `build(...)`
call in `main()` to:
```python
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.out)
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: PASS.

- [ ] **Step 5: Run the FULL suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: all tests pass (core slice + stroke-order additions).

- [ ] **Step 6: Add KanjiVG to the fetch script**

In `data-pipeline/scripts/fetch_sources.sh`, before the final `echo "Done..."`
line, add:

```bash
echo "Fetching KanjiVG..."
curl -fsSL "https://github.com/KanjiVG/kanjivg/releases/download/r20240807/kanjivg-20240807.xml.gz" -o sources/kanjivg.xml.gz
gunzip -f sources/kanjivg.xml.gz   # -> sources/kanjivg.xml
```

> If that release tag 404s, pick the latest tag from
> https://github.com/KanjiVG/kanjivg/releases and update both the tag and the
> filename. The XML structure is stable across releases.

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/build_db.py data-pipeline/tests/test_build_db.py data-pipeline/scripts/fetch_sources.sh
git commit -m "feat(data-pipeline): build_db loads KanjiVG stroke order + fetch step"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `stroke_order` table (spec §4) → Task 1; `parse_kanjivg`
  (§5) → Task 2; `load_stroke_order` by codepoint (§5/§6) → Task 3;
  `missing_stroke_order` gate (§5) → Task 4; orchestrator `kanjivg_path` stage +
  fetch (§5/§6) → Task 5; tests (§7) distributed across Tasks 2–5.
- **Breaking change handled:** `build()` gains a required `kanjivg_path`
  parameter; the only caller in the repo's tests is updated (Task 5 Step 1).
  Note: the app's placeholder-DB generation command (in the app-scaffold plan)
  predates this and would now also need a `kanjivg` fixture argument — out of
  scope here; the app's current kanji-list screen does not read `stroke_order`,
  so the committed placeholder DB remains valid until the writing canvas is built.
- **Pre-existing test impact:** the new gate makes the old
  `test_assert_core_gates_passes_on_complete_data` require strokes; Task 4 Step 5
  updates exactly that test and no other.
- **Type consistency:** `parse_kanjivg -> dict[int, list[str]]`,
  `load_stroke_order(conn, strokes_by_codepoint)`, and the
  `missing_stroke_order` report key are used identically across Tasks 2–5.
- **No placeholders:** every code/test step contains complete content.

## Follow-on (not in this plan)

JMdict words, Tatoeba sentences, WordNet relations, Korean 훈, LLM 4-language
glosses — each its own plan. The app's writing canvas (which consumes
`stroke_order`) is a separate app sub-project.

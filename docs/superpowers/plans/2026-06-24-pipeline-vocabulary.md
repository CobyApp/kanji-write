# Data Pipeline — Vocabulary (JMdict) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add common JMdict words (surface, kana reading, English gloss) linked to the jōyō kanji they contain, so the study card can show usage vocabulary.

**Architecture:** Add `word`/`word_kanji`/`word_gloss` tables. A `parse_jmdict` ingester yields common kanji-bearing words; `load_words` stores them and links each to the jōyō kanji in its surface; the orchestrator gains a `jmdict_path` stage; an informational (non-gating) `kanji_without_words` report field is added. Additive — core gates unchanged.

**Tech Stack:** Python 3.11+, lxml, sqlite3, pytest. Commands from repo root; venv at `data-pipeline/.venv`; `git` from repo root.

---

## File Structure (this slice)

```
data-pipeline/
├── kanjipipe/
│   ├── models.py             # + Word dataclass (modify)
│   ├── schema.py             # + word/word_kanji/word_gloss (modify)
│   ├── ingest/jmdict.py      # parse_jmdict (new)
│   ├── loader.py             # + load_words (modify)
│   ├── validate.py           # + kanji_without_words report (modify)
│   └── build_db.py           # + jmdict_path stage (modify)
├── scripts/fetch_sources.sh  # + JMdict fetch (modify)
└── tests/
    ├── fixtures/jmdict_sample.xml   # (new)
    ├── test_jmdict.py               # (new)
    ├── test_loader.py               # + word cases (modify)
    ├── test_validate.py             # + report field (modify)
    ├── test_db.py                   # + tables (modify)
    └── test_build_db.py             # + jmdict_path + word assert (modify)
```

---

## Task 1: Schema + Word model + fixture

**Files:**
- Modify: `data-pipeline/kanjipipe/models.py`
- Modify: `data-pipeline/kanjipipe/schema.py`
- Modify: `data-pipeline/tests/test_db.py`
- Create: `data-pipeline/tests/fixtures/jmdict_sample.xml`

- [ ] **Step 1: Add the failing table-exists assertion**

In `data-pipeline/tests/test_db.py`, change the table-set assertion in
`test_init_db_creates_core_tables` to also require the word tables:

```python
    assert {"kanji", "reading", "gloss", "stroke_order",
            "word", "word_kanji", "word_gloss"} <= tables
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: FAIL — word tables missing.

- [ ] **Step 3: Add the tables to the schema**

In `data-pipeline/kanjipipe/schema.py`, append to the `DDL` string (before the
closing `"""`):

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
    lang    TEXT NOT NULL,
    text    TEXT NOT NULL
);

CREATE INDEX idx_word_kanji_kanji ON word_kanji(kanji_id);
CREATE INDEX idx_word_gloss_word ON word_gloss(word_id);
```

- [ ] **Step 4: Add the Word model**

In `data-pipeline/kanjipipe/models.py`, append:

```python
@dataclass
class Word:
    surface: str
    reading_kana: str
    is_common: bool = True
    en_glosses: list[str] = field(default_factory=list)
```

(`dataclass` and `field` are already imported at the top of the file.)

- [ ] **Step 5: Create the JMdict fixture**

Create `data-pipeline/tests/fixtures/jmdict_sample.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<JMdict>
<entry>
  <ent_seq>1</ent_seq>
  <k_ele><keb>山</keb><ke_pri>news1</ke_pri></k_ele>
  <r_ele><reb>やま</reb><re_pri>news1</re_pri></r_ele>
  <sense><gloss>mountain</gloss><gloss>hill</gloss></sense>
</entry>
<entry>
  <ent_seq>2</ent_seq>
  <k_ele><keb>学校</keb><ke_pri>ichi1</ke_pri></k_ele>
  <r_ele><reb>がっこう</reb><re_pri>ichi1</re_pri></r_ele>
  <sense><gloss>school</gloss></sense>
</entry>
<entry>
  <ent_seq>3</ent_seq>
  <k_ele><keb>山岳</keb></k_ele>
  <r_ele><reb>さんがく</reb></r_ele>
  <sense><gloss>mountains</gloss></sense>
</entry>
<entry>
  <ent_seq>4</ent_seq>
  <r_ele><reb>これ</reb><re_pri>ichi1</re_pri></r_ele>
  <sense><gloss>this</gloss></sense>
</entry>
</JMdict>
```

Entry 1 (山) and 2 (学校) are common with a kanji form. Entry 3 (山岳) has no
priority tag → dropped. Entry 4 (これ) is kana-only (no `keb`) → dropped.

- [ ] **Step 6: Run the table test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/models.py data-pipeline/kanjipipe/schema.py data-pipeline/tests/test_db.py data-pipeline/tests/fixtures/jmdict_sample.xml
git commit -m "feat(data-pipeline): word tables + Word model + JMdict fixture"
```

---

## Task 2: JMdict parser (TDD)

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/jmdict.py`
- Create: `data-pipeline/tests/test_jmdict.py`

- [ ] **Step 1: Write the failing test**

Create `data-pipeline/tests/test_jmdict.py`:

```python
# tests/test_jmdict.py
from pathlib import Path

from kanjipipe.ingest.jmdict import parse_jmdict

FIXTURE = Path(__file__).parent / "fixtures" / "jmdict_sample.xml"


def test_keeps_only_common_entries_with_kanji():
    words = parse_jmdict(FIXTURE)
    assert [w.surface for w in words] == ["山", "学校"]  # 山岳 (no pri) + これ (no keb) dropped


def test_extracts_reading_and_english_glosses():
    yama = next(w for w in parse_jmdict(FIXTURE) if w.surface == "山")
    assert yama.reading_kana == "やま"
    assert yama.en_glosses == ["mountain", "hill"]


def test_gloss_count_capped_at_three(tmp_path):
    p = tmp_path / "j.xml"
    p.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<JMdict><entry>'
        '<k_ele><keb>例</keb><ke_pri>news1</ke_pri></k_ele>'
        '<r_ele><reb>れい</reb></r_ele>'
        '<sense><gloss>a</gloss><gloss>b</gloss><gloss>c</gloss><gloss>d</gloss></sense>'
        '</entry></JMdict>',
        encoding="utf-8")
    assert parse_jmdict(p)[0].en_glosses == ["a", "b", "c"]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_jmdict.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'kanjipipe.ingest.jmdict'`.

- [ ] **Step 3: Write the parser**

Create `data-pipeline/kanjipipe/ingest/jmdict.py`:

```python
"""Parse JMdict into common kanji-bearing words with English glosses."""
from pathlib import Path

from lxml import etree

from kanjipipe.models import Word

_XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
_MAX_GLOSSES = 3


def parse_jmdict(path: str | Path) -> list[Word]:
    # JMdict ships an internal DTD with entity definitions (e.g. &n;); lxml
    # resolves internal entities by default. no_network avoids fetching anything.
    parser = etree.XMLParser(resolve_entities=True, no_network=True)
    root = etree.parse(str(path), parser).getroot()

    words: list[Word] = []
    for entry in root.iterfind("entry"):
        kebs = entry.findall("k_ele/keb")
        if not kebs or not kebs[0].text:
            continue  # kana-only entry — no kanji to attach to
        is_common = (entry.find("k_ele/ke_pri") is not None
                     or entry.find("r_ele/re_pri") is not None)
        if not is_common:
            continue
        reb = entry.find("r_ele/reb")
        if reb is None or not reb.text:
            continue

        glosses: list[str] = []
        for gloss in entry.iterfind("sense/gloss"):
            lang = gloss.get(_XML_LANG)
            if (lang is None or lang == "eng") and gloss.text:
                glosses.append(gloss.text)
                if len(glosses) >= _MAX_GLOSSES:
                    break

        words.append(Word(
            surface=kebs[0].text,
            reading_kana=reb.text,
            is_common=True,
            en_glosses=glosses,
        ))
    return words
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_jmdict.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/ingest/jmdict.py data-pipeline/tests/test_jmdict.py
git commit -m "feat(data-pipeline): JMdict parser (common kanji words + EN glosses)"
```

---

## Task 3: load_words (TDD)

**Files:**
- Modify: `data-pipeline/kanjipipe/loader.py`
- Modify: `data-pipeline/tests/test_loader.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_loader.py`:

```python
from kanjipipe.loader import load_words
from kanjipipe.models import Word


def _gaku():
    return Kanji(literal="学", codepoint=0x5B66, stroke_count=8, grade=1,
                 freq_rank=63, radical=39, jlpt_level="N5",
                 readings=[Reading("on", "ガク")], glosses=[Gloss("en", "study")])


def test_load_words_links_each_joyo_kanji_in_surface():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama(), _gaku()])  # 山, 学

    load_words(conn, [
        Word(surface="学校", reading_kana="がっこう", en_glosses=["school"]),
        Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
    ])

    # 学校 links to 学 (校 is not a seeded kanji, so no link to it)
    gakkou_links = conn.execute(
        "SELECT k.literal FROM word_kanji wk "
        "JOIN word w ON wk.word_id = w.id JOIN kanji k ON wk.kanji_id = k.id "
        "WHERE w.surface = '学校'").fetchall()
    assert gakkou_links == [("学",)]

    # gloss stored
    gloss = conn.execute(
        "SELECT lang, text FROM word_gloss g JOIN word w ON g.word_id = w.id "
        "WHERE w.surface = '山'").fetchone()
    assert gloss == ("en", "mountain")


def test_load_words_word_without_joyo_kanji_has_no_links():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_words(conn, [Word(surface="校", reading_kana="こう", en_glosses=["school"])])
    assert conn.execute("SELECT COUNT(*) FROM word").fetchone()[0] == 1
    assert conn.execute("SELECT COUNT(*) FROM word_kanji").fetchone()[0] == 0
```

(`_yama()`, `init_db`, `load_kanji`, `Kanji`/`Reading`/`Gloss` are already
imported/defined in this test file from earlier tasks.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: FAIL — `cannot import name 'load_words'`.

- [ ] **Step 3: Implement the loader**

Append to `data-pipeline/kanjipipe/loader.py`:

```python
def load_words(conn: sqlite3.Connection, words: list["Word"]) -> None:
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    for word in words:
        cur = conn.execute(
            "INSERT INTO word (surface, reading_kana, is_common) VALUES (?, ?, ?)",
            (word.surface, word.reading_kana, 1 if word.is_common else 0),
        )
        word_id = cur.lastrowid
        for gloss in word.en_glosses:
            conn.execute(
                "INSERT INTO word_gloss (word_id, lang, text) VALUES (?, 'en', ?)",
                (word_id, gloss),
            )
        linked: set[int] = set()
        for char in word.surface:
            kanji_id = kanji_id_by_literal.get(char)
            if kanji_id is not None and kanji_id not in linked:
                conn.execute(
                    "INSERT INTO word_kanji (word_id, kanji_id) VALUES (?, ?)",
                    (word_id, kanji_id),
                )
                linked.add(kanji_id)
    conn.commit()
```

Add the import at the top of `loader.py` (it already imports `Kanji`):
```python
from kanjipipe.models import Kanji, Word
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/loader.py data-pipeline/tests/test_loader.py
git commit -m "feat(data-pipeline): load_words links words to jōyō kanji by surface"
```

---

## Task 4: kanji_without_words report (TDD, non-gating)

**Files:**
- Modify: `data-pipeline/kanjipipe/validate.py`
- Modify: `data-pipeline/tests/test_validate.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_validate.py` (add `load_words` + `Word` to the
existing imports — the `from kanjipipe.loader import ...` and
`from kanjipipe.models import ...` lines):

```python
def test_coverage_report_counts_kanji_without_words():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                 # 山, codepoint 0x5C71
    load_stroke_order(conn, {0x5C71: ["d1"]})
    # no words yet → 山 counts as missing words
    assert coverage_report(conn)["kanji_without_words"] == 1


def test_assert_core_gates_does_not_fail_on_missing_words():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    # gate passes even though 山 has no words (vocabulary is supplementary)
    assert assert_core_gates(conn)["kanji_without_words"] == 1
```

To support these, update the import lines at the top of `test_validate.py`:
```python
from kanjipipe.loader import load_kanji, load_stroke_order, load_words
from kanjipipe.models import Gloss, Kanji, Reading, Word
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: FAIL — `coverage_report` has no `kanji_without_words` key.

- [ ] **Step 3: Add the report field (not the gate)**

In `data-pipeline/kanjipipe/validate.py`, add to the dict returned by
`coverage_report` (after `missing_stroke_order`):

```python
        "kanji_without_words": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM word_kanji wk WHERE wk.kanji_id = k.id)"),
```

Do **not** add anything to `assert_core_gates` — words are supplementary and
must not fail the build.

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/validate.py data-pipeline/tests/test_validate.py
git commit -m "feat(data-pipeline): report kanji_without_words (non-gating)"
```

---

## Task 5: Orchestrator integration + fetch

**Files:**
- Modify: `data-pipeline/kanjipipe/build_db.py`
- Modify: `data-pipeline/tests/test_build_db.py`
- Modify: `data-pipeline/scripts/fetch_sources.sh`

- [ ] **Step 1: Update the integration test (failing)**

In `data-pipeline/tests/test_build_db.py`, update the `build(...)` call to pass
`jmdict_path` and add a word assertion. Replace the `build(...)` call and add the
assertion block — the test becomes:

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
        jmdict_path=FIX / "jmdict_sample.xml",
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
        # 山 has the word 山 linked
        yama_words = conn.execute(
            "SELECT w.surface FROM word w "
            "JOIN word_kanji wk ON wk.word_id = w.id "
            "JOIN kanji k ON wk.kanji_id = k.id "
            "WHERE k.literal = '山' ORDER BY w.surface").fetchall()
        assert ("山",) in yama_words
    conn.close()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: FAIL — `build()` got an unexpected keyword argument `jmdict_path`.

- [ ] **Step 3: Wire JMdict into the orchestrator**

In `data-pipeline/kanjipipe/build_db.py`:

(a) add imports:
```python
from kanjipipe.ingest.jmdict import parse_jmdict
```
and extend the loader import to include `load_words`:
```python
from kanjipipe.loader import load_kanji, load_stroke_order, load_words
```

(b) replace the `build` function with:
```python
def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    jmdict_path: str | Path,
    out_path: str,
) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)
    strokes = parse_kanjivg(kanjivg_path)
    words = parse_jmdict(jmdict_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    try:
        load_kanji(conn, kanji)
        load_stroke_order(conn, strokes)
        load_words(conn, words)
        report = assert_core_gates(conn)  # raises if a gate fails
    finally:
        conn.close()  # always release the handle, even on gate failure
    return report
```

(c) in `main()`, add the argument and pass it:
```python
    parser.add_argument("--jmdict", default="sources/jmdict.xml")
```
and update the call to:
```python
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.jmdict, args.out)
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: PASS.

- [ ] **Step 5: Run the FULL suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: all tests pass.

- [ ] **Step 6: Add JMdict to the fetch script**

In `data-pipeline/scripts/fetch_sources.sh`, before the final `echo "Done..."`
line, add:

```bash
echo "Fetching JMdict (English)..."
curl -fsSL "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz" -o sources/jmdict.xml.gz
gunzip -f sources/jmdict.xml.gz   # -> sources/jmdict.xml
```

> JMdict_e is the English-only edition (EDRDG, CC BY-SA 4.0), smaller than the
> multilingual JMdict and sufficient for v1 word glosses.

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/build_db.py data-pipeline/tests/test_build_db.py data-pipeline/scripts/fetch_sources.sh
git commit -m "feat(data-pipeline): build_db loads JMdict words + fetch step"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** word tables (spec §4) → Task 1; `parse_jmdict` (§5) → Task 2;
  `load_words` link-by-surface (§5/§6) → Task 3; `kanji_without_words`
  non-gating report (§5) → Task 4; orchestrator `jmdict_path` + fetch (§5/§6) →
  Task 5; tests (§7) across Tasks 2–5.
- **Breaking change handled:** `build()` gains a required `jmdict_path`; the only
  caller in tests is updated (Task 5 Step 1). Note: regenerating the real
  bundled DB now also requires `sources/jmdict.xml` (the fetch step adds it).
- **Non-gating confirmed:** `kanji_without_words` is report-only; `assert_core_gates`
  is unchanged, so kanji lacking common words do not fail the build.
- **Type consistency:** `parse_jmdict -> list[Word]`, `Word{surface,
  reading_kana, is_common, en_glosses}`, `load_words(conn, words)`, and the
  `kanji_without_words` report key are used identically across Tasks 1–5.
- **DTD/entities:** `parse_jmdict` uses an lxml parser with `resolve_entities=True`
  so JMdict's internal entity definitions (e.g. `&n;` in `<pos>`) parse without
  error; the fixture omits a DTD for simplicity.

## Follow-on (not in this plan)

Tatoeba example sentences, WordNet synonym/antonym relations, Korean 훈, LLM
4-language glosses, and the study-card UI that displays words.

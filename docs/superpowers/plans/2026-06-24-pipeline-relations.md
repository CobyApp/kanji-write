# Data Pipeline — Word Relations (JMdict antonym/related) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add word-level antonym (`<ant>`) and related (`<xref>`) relations from JMdict so the study card can show 反意語 / 関連語.

**Architecture:** Add a `relation` table. A `parse_jmdict_relations` ingester (streaming, like the word parser) yields `(source_surface, target_surface, type)` from each entry's `<ant>`/`<xref>`; `load_relations` materializes a row only when both surfaces resolve to stored common words. The orchestrator reuses the existing `jmdict_path` (no new parameter). Additive — validate/gates unchanged.

**Tech Stack:** Python 3.11+, lxml, sqlite3, pytest. Commands from repo root; venv at `data-pipeline/.venv`; `git` from repo root.

---

## File Structure (this slice)

```
data-pipeline/
├── kanjipipe/
│   ├── models.py                   # + Relation dataclass (modify)
│   ├── schema.py                   # + relation table (modify)
│   ├── ingest/jmdict_relations.py  # parse_jmdict_relations (new)
│   ├── loader.py                   # + load_relations (modify)
│   └── build_db.py                 # + relations stage (modify)
└── tests/
    ├── fixtures/jmdict_sample.xml  # + <ant>/<xref> on entries 1 & 2 (modify)
    ├── test_jmdict_relations.py    # (new)
    ├── test_loader.py              # + relation cases (modify)
    ├── test_db.py                  # + relation table (modify)
    └── test_build_db.py            # + relation assertion (modify)
```

---

## Task 1: Schema + Relation model + fixture additions

**Files:**
- Modify: `data-pipeline/kanjipipe/models.py`
- Modify: `data-pipeline/kanjipipe/schema.py`
- Modify: `data-pipeline/tests/test_db.py`
- Modify: `data-pipeline/tests/fixtures/jmdict_sample.xml`

- [ ] **Step 1: Add the failing table-exists assertion**

In `data-pipeline/tests/test_db.py`, extend the table-set assertion to include
`relation`:

```python
    assert {"kanji", "reading", "gloss", "stroke_order",
            "word", "word_kanji", "word_gloss",
            "sentence", "sentence_translation", "sentence_kanji",
            "relation"} <= tables
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: FAIL — `relation` table missing.

- [ ] **Step 3: Add the table to the schema**

In `data-pipeline/kanjipipe/schema.py`, append to the `DDL` string (before the
closing `"""`):

```sql
CREATE TABLE relation (
    id        INTEGER PRIMARY KEY,
    word_id_a INTEGER NOT NULL REFERENCES word(id),
    word_id_b INTEGER NOT NULL REFERENCES word(id),
    type      TEXT NOT NULL,
    UNIQUE(word_id_a, word_id_b, type)
);

CREATE INDEX idx_relation_a ON relation(word_id_a);
```

- [ ] **Step 4: Add the Relation model**

In `data-pipeline/kanjipipe/models.py`, append:

```python
@dataclass
class Relation:
    source_surface: str
    target_surface: str
    type: str
```

- [ ] **Step 5: Add `<ant>`/`<xref>` to the JMdict fixture**

In `data-pipeline/tests/fixtures/jmdict_sample.xml`, modify entry 1 (山) and
entry 2 (学校) senses to carry a cross-reference and an antonym between the two
common words. The two entries become:

```xml
<entry>
  <ent_seq>1</ent_seq>
  <k_ele><keb>山</keb><ke_pri>news1</ke_pri></k_ele>
  <r_ele><reb>やま</reb><re_pri>news1</re_pri></r_ele>
  <sense><gloss>mountain</gloss><gloss>hill</gloss><xref>学校</xref></sense>
</entry>
<entry>
  <ent_seq>2</ent_seq>
  <k_ele><keb>学校</keb><ke_pri>ichi1</ke_pri></k_ele>
  <r_ele><reb>がっこう</reb><re_pri>ichi1</re_pri></r_ele>
  <sense><gloss>school</gloss><ant>山・やま・1</ant></sense>
</entry>
```

(The `<ant>` target uses the `語・よみ・senseNo` form to exercise `・` stripping.
Entries 3 and 4 are unchanged. The word parser ignores `<ant>`/`<xref>`, so the
existing `test_jmdict.py` tests stay green.)

- [ ] **Step 6: Run the table test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py tests/test_jmdict.py -q`
Expected: PASS (table test green; existing JMdict word tests still green).

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/models.py data-pipeline/kanjipipe/schema.py data-pipeline/tests/test_db.py data-pipeline/tests/fixtures/jmdict_sample.xml
git commit -m "feat(data-pipeline): relation table + Relation model + fixture ant/xref"
```

---

## Task 2: JMdict relations parser (TDD)

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/jmdict_relations.py`
- Create: `data-pipeline/tests/test_jmdict_relations.py`

- [ ] **Step 1: Write the failing test**

Create `data-pipeline/tests/test_jmdict_relations.py`:

```python
# tests/test_jmdict_relations.py
from pathlib import Path

from kanjipipe.ingest.jmdict_relations import parse_jmdict_relations

FIXTURE = Path(__file__).parent / "fixtures" / "jmdict_sample.xml"


def test_extracts_antonym_and_related_with_target_stripped():
    relations = parse_jmdict_relations(FIXTURE)
    tuples = {(r.source_surface, r.target_surface, r.type) for r in relations}
    assert ("山", "学校", "related") in tuples       # from 山's <xref>学校</xref>
    assert ("学校", "山", "antonym") in tuples        # from 学校's <ant>山・やま・1</ant>, stripped to 山


def test_entries_without_relations_produce_none():
    # Only entries 1 and 2 carry ant/xref → exactly two relations.
    assert len(parse_jmdict_relations(FIXTURE)) == 2
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_jmdict_relations.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'kanjipipe.ingest.jmdict_relations'`.

- [ ] **Step 3: Write the parser**

Create `data-pipeline/kanjipipe/ingest/jmdict_relations.py`:

```python
"""Parse JMdict antonym (<ant>) and cross-reference (<xref>) relations."""
from pathlib import Path

from lxml import etree

from kanjipipe.models import Relation


def _preferred_keb(entry) -> str | None:
    k_eles = entry.findall("k_ele")
    for k_ele in k_eles:
        keb = k_ele.findtext("keb")
        if keb and k_ele.find("ke_inf") is None:
            return keb
    return (k_eles[0].findtext("keb") if k_eles else None) or None


def _target_surface(text: str | None) -> str | None:
    # JMdict xref/ant targets look like "語・よみ・senseNo"; keep the surface only.
    if not text:
        return None
    return text.split("・", 1)[0] or None


def _entry_relations(entry) -> list[Relation]:
    source = _preferred_keb(entry)
    if source is None:
        return []
    relations: list[Relation] = []
    for sense in entry.iterfind("sense"):
        for ant in sense.iterfind("ant"):
            target = _target_surface(ant.text)
            if target:
                relations.append(Relation(source, target, "antonym"))
        for xref in sense.iterfind("xref"):
            target = _target_surface(xref.text)
            if target:
                relations.append(Relation(source, target, "related"))
    return relations


def parse_jmdict_relations(path: str | Path) -> list[Relation]:
    relations: list[Relation] = []
    for _event, entry in etree.iterparse(
        str(path), events=("end",), tag="entry",
        resolve_entities=True, no_network=True,
    ):
        relations.extend(_entry_relations(entry))
        entry.clear()
    return relations
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_jmdict_relations.py -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/ingest/jmdict_relations.py data-pipeline/tests/test_jmdict_relations.py
git commit -m "feat(data-pipeline): JMdict relations parser (antonym/related)"
```

---

## Task 3: load_relations (TDD)

**Files:**
- Modify: `data-pipeline/kanjipipe/loader.py`
- Modify: `data-pipeline/tests/test_loader.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_loader.py`:

```python
def test_load_relations_links_stored_words_only():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_words(conn, [
        Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
        Word(surface="学校", reading_kana="がっこう", en_glosses=["school"]),
    ])

    load_relations(conn, [
        Relation(source_surface="山", target_surface="学校", type="related"),
        Relation(source_surface="山", target_surface="未登録語", type="antonym"),  # target not stored
    ])

    rows = conn.execute(
        "SELECT a.surface, b.surface, r.type FROM relation r "
        "JOIN word a ON r.word_id_a = a.id JOIN word b ON r.word_id_b = b.id"
    ).fetchall()
    assert rows == [("山", "学校", "related")]   # the unstored-target relation is skipped


def test_load_relations_dedupes_via_unique():
    conn = init_db(":memory:")
    load_words(conn, [
        Word(surface="山", reading_kana="やま", en_glosses=[]),
        Word(surface="学校", reading_kana="がっこう", en_glosses=[]),
    ])
    rel = Relation(source_surface="山", target_surface="学校", type="related")
    load_relations(conn, [rel, rel])  # duplicate
    assert conn.execute("SELECT COUNT(*) FROM relation").fetchone()[0] == 1
```

Add `load_relations` and `Relation` to the existing top imports of
`test_loader.py`:
```python
from kanjipipe.loader import load_kanji, load_relations, load_sentences, load_stroke_order, load_words
from kanjipipe.models import Gloss, Kanji, Reading, Relation, Sentence, Word
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: FAIL — `cannot import name 'load_relations'`.

- [ ] **Step 3: Implement the loader**

Append to `data-pipeline/kanjipipe/loader.py`:

```python
def load_relations(conn: sqlite3.Connection, relations: list["Relation"]) -> None:
    word_id_by_surface: dict[str, int] = {}
    for word_id, surface in conn.execute("SELECT id, surface FROM word"):
        word_id_by_surface.setdefault(surface, word_id)  # first id wins on duplicates
    for relation in relations:
        a = word_id_by_surface.get(relation.source_surface)
        b = word_id_by_surface.get(relation.target_surface)
        if a is None or b is None or a == b:
            continue
        conn.execute(
            "INSERT OR IGNORE INTO relation (word_id_a, word_id_b, type) "
            "VALUES (?, ?, ?)",
            (a, b, relation.type),
        )
    conn.commit()
```

Update the models import at the top of `loader.py` to include `Relation`:
```python
from kanjipipe.models import Kanji, Relation, Sentence, Word
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/loader.py data-pipeline/tests/test_loader.py
git commit -m "feat(data-pipeline): load_relations links stored words (INSERT OR IGNORE)"
```

---

## Task 4: Orchestrator integration

**Files:**
- Modify: `data-pipeline/kanjipipe/build_db.py`
- Modify: `data-pipeline/tests/test_build_db.py`

- [ ] **Step 1: Add the failing relation assertion**

In `data-pipeline/tests/test_build_db.py`, inside the
`with sqlite3.connect(out) as conn:` block (after the sentence assertions, before
the closing of the `with`), add:

```python
        # 山 ↔ 学校 relation materialized from JMdict ant/xref
        rel = conn.execute(
            "SELECT a.surface, b.surface, r.type FROM relation r "
            "JOIN word a ON r.word_id_a = a.id JOIN word b ON r.word_id_b = b.id "
            "ORDER BY r.type").fetchall()
        assert ("山", "学校", "related") in rel
        assert ("学校", "山", "antonym") in rel
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: FAIL — no `relation` rows (build doesn't load relations yet).

- [ ] **Step 3: Wire relations into the orchestrator**

In `data-pipeline/kanjipipe/build_db.py`:

(a) add the import:
```python
from kanjipipe.ingest.jmdict_relations import parse_jmdict_relations
```
and extend the loader import to include `load_relations`:
```python
from kanjipipe.loader import (
    load_kanji, load_relations, load_sentences, load_stroke_order, load_words)
```

(b) in `build()`, parse relations alongside the other sources (after
`words = parse_jmdict(jmdict_path)`):
```python
    relations = parse_jmdict_relations(jmdict_path)
```
and load them after `load_words` (relations resolve against the `word` table, so
words must be loaded first):
```python
        load_words(conn, words)
        load_relations(conn, relations)
        load_sentences(conn, sentences)
```

(No signature change — relations reuse `jmdict_path`.)

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: PASS.

- [ ] **Step 5: Run the FULL suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/build_db.py data-pipeline/tests/test_build_db.py
git commit -m "feat(data-pipeline): build_db loads JMdict word relations"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `relation` table (spec §4) → Task 1; `parse_jmdict_relations`
  (§5) → Task 2; `load_relations` stored-words-only + dedup (§5/§6) → Task 3;
  orchestrator integration reusing `jmdict_path` (§5/§6) → Task 4; tests (§7)
  across Tasks 2–4.
- **No signature change:** relations are parsed from the existing `jmdict_path`,
  so `build()` is unchanged — no caller updates beyond the new assertion.
- **validate.py untouched:** relations are word-level and supplementary; no gate
  or report change, per spec §5.
- **Surface matching consistency:** `parse_jmdict_relations._preferred_keb`
  mirrors the word parser's surface choice (first non-`ke_inf` keb), so a
  relation's `source_surface` matches how the word was stored, maximizing
  resolution in `load_relations`.
- **Type consistency:** `Relation{source_surface, target_surface, type}`,
  `parse_jmdict_relations(path) -> list[Relation]`, and `load_relations(conn,
  relations)` are used identically across tasks.
- **Existing JMdict tests unaffected:** `<ant>`/`<xref>` added to the fixture are
  ignored by the word parser (`parse_jmdict`), verified by re-running
  `test_jmdict.py` in Task 1 Step 6.

## Follow-on (not in this plan)

Japanese WordNet true synonyms, Korean 훈, LLM 4-language glosses, and the
study-card UI that displays relations.

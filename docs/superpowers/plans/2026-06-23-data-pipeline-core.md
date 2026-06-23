# Data Pipeline — Core Kanji Data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundation of the `data-pipeline/` Python project that ingests KANJIDIC2, filters to the 2,136 jōyō kanji, merges JLPT N5–N1 levels, and emits a versioned `kanji.sqlite` containing each kanji's core fields, readings (on/kun/pinyin/Korean音), and English meaning — all gated by a coverage check.

**Architecture:** Per-source ingester functions parse raw files into plain `Kanji` dataclasses; a loader writes them to SQLite; a validator enforces coverage gates; an orchestrator (`build_db.py`) wires the stages and emits `out/kanji.sqlite`. This plan covers only the KANJIDIC2 core slice — stroke order (KanjiVG), words (JMdict), sentences (Tatoeba), relations (WordNet), Korean 훈, and LLM gap-fill are separate follow-on plans that extend the same schema and orchestrator.

**Tech Stack:** Python 3.11+, lxml (XML parsing), sqlite3 (stdlib), pytest.

---

## File Structure

```
data-pipeline/
├── pyproject.toml                 # project + deps (lxml, pytest)
├── scripts/fetch_sources.sh       # download KANJIDIC2 + JLPT list into sources/
├── kanjipipe/
│   ├── __init__.py
│   ├── models.py                  # Kanji / Reading / Gloss dataclasses
│   ├── schema.py                  # SQLite DDL (kanji, reading, gloss)
│   ├── db.py                      # init_db() — connect + create schema
│   ├── ingest/
│   │   ├── __init__.py
│   │   ├── kanjidic2.py           # parse_kanjidic2() → list[Kanji]
│   │   └── jlpt.py                # merge_jlpt()
│   ├── filters.py                 # filter_joyo()
│   ├── loader.py                  # load_kanji()
│   ├── validate.py                # coverage_report(), assert_core_gates()
│   └── build_db.py                # build() orchestrator
└── tests/
    ├── __init__.py
    ├── fixtures/
    │   ├── kanjidic2_sample.xml
    │   └── jlpt_sample.json
    ├── test_kanjidic2.py
    ├── test_filters.py
    ├── test_jlpt.py
    ├── test_loader.py
    ├── test_validate.py
    └── test_build_db.py
```

Each file has one responsibility: parsing is isolated per source under `ingest/`,
persistence in `loader.py`, gates in `validate.py`, wiring in `build_db.py`.

---

## Task 0: Project setup

**Files:**
- Create: `data-pipeline/pyproject.toml`
- Create: `data-pipeline/kanjipipe/__init__.py` (empty)
- Create: `data-pipeline/kanjipipe/ingest/__init__.py` (empty)
- Create: `data-pipeline/tests/__init__.py` (empty)

- [ ] **Step 1: Create `pyproject.toml`**

```toml
[project]
name = "kanjipipe"
version = "0.1.0"
description = "Data pipeline that compiles open kanji datasets into kanji.sqlite"
requires-python = ">=3.11"
dependencies = ["lxml>=5.0"]

[project.optional-dependencies]
dev = ["pytest>=8.0"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"
```

- [ ] **Step 2: Create the empty package files**

Create `data-pipeline/kanjipipe/__init__.py`, `data-pipeline/kanjipipe/ingest/__init__.py`, and `data-pipeline/tests/__init__.py` as empty files.

- [ ] **Step 3: Create a virtualenv and install**

Run:
```bash
cd data-pipeline
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
```
Expected: installs lxml + pytest, `Successfully installed ... kanjipipe-0.1.0`.

- [ ] **Step 4: Verify pytest runs (no tests yet)**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: `no tests ran` (exit code 5 is fine at this stage).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/pyproject.toml data-pipeline/kanjipipe data-pipeline/tests
git commit -m "chore(data-pipeline): project skeleton (pyproject, package layout)"
```

---

## Task 1: Domain models

**Files:**
- Create: `data-pipeline/kanjipipe/models.py`
- Test: `data-pipeline/tests/test_models.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_models.py
from kanjipipe.models import Kanji, Reading, Gloss


def test_kanji_defaults_to_empty_readings_and_glosses():
    k = Kanji(literal="山", codepoint=0x5C71, stroke_count=3,
              grade=1, freq_rank=360, radical=46)
    assert k.readings == []
    assert k.glosses == []
    assert k.jlpt_level is None


def test_reading_and_gloss_hold_values():
    r = Reading(lang_axis="on", value="サン")
    g = Gloss(lang="en", text="mountain")
    assert r.is_common is True
    assert (g.lang, g.text) == ("en", "mountain")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_models.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.models'`.

- [ ] **Step 3: Write the implementation**

```python
# kanjipipe/models.py
from dataclasses import dataclass, field


@dataclass
class Reading:
    lang_axis: str  # 'on' | 'kun' | 'pinyin' | 'eum'
    value: str
    is_common: bool = True


@dataclass
class Gloss:
    lang: str  # 'ko' | 'ja' | 'zh' | 'en'
    text: str


@dataclass
class Kanji:
    literal: str
    codepoint: int          # Unicode scalar (UCS)
    stroke_count: int
    grade: int | None       # 1-6 = 小, 8 = 中学/常用
    freq_rank: int | None
    radical: int | None     # classical radical number
    jlpt_level: str | None = None  # 'N5'..'N1'
    readings: list[Reading] = field(default_factory=list)
    glosses: list[Gloss] = field(default_factory=list)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_models.py -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/models.py data-pipeline/tests/test_models.py
git commit -m "feat(data-pipeline): Kanji/Reading/Gloss domain models"
```

---

## Task 2: SQLite schema + db initializer

**Files:**
- Create: `data-pipeline/kanjipipe/schema.py`
- Create: `data-pipeline/kanjipipe/db.py`
- Test: `data-pipeline/tests/test_db.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_db.py
from kanjipipe.db import init_db


def test_init_db_creates_core_tables():
    conn = init_db(":memory:")
    tables = {row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"kanji", "reading", "gloss"} <= tables


def test_init_db_enables_foreign_keys():
    conn = init_db(":memory:")
    assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.db'`.

- [ ] **Step 3: Write the schema**

```python
# kanjipipe/schema.py
DDL = """
CREATE TABLE kanji (
    id           INTEGER PRIMARY KEY,
    literal      TEXT    NOT NULL UNIQUE,
    codepoint    INTEGER NOT NULL,
    stroke_count INTEGER NOT NULL,
    grade        INTEGER,
    jlpt_level   TEXT,
    freq_rank    INTEGER,
    radical      INTEGER
);

CREATE TABLE reading (
    id        INTEGER PRIMARY KEY,
    kanji_id  INTEGER NOT NULL REFERENCES kanji(id),
    lang_axis TEXT    NOT NULL,   -- 'on' | 'kun' | 'pinyin' | 'eum'
    value     TEXT    NOT NULL,
    is_common INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE gloss (
    id       INTEGER PRIMARY KEY,
    kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    lang     TEXT    NOT NULL,    -- 'ko' | 'ja' | 'zh' | 'en'
    text     TEXT    NOT NULL
);

CREATE INDEX idx_reading_kanji ON reading(kanji_id);
CREATE INDEX idx_gloss_kanji   ON gloss(kanji_id);
"""
```

- [ ] **Step 4: Write the db initializer**

```python
# kanjipipe/db.py
import sqlite3

from kanjipipe.schema import DDL


def init_db(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(DDL)
    conn.commit()
    return conn
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: PASS (2 passed).

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/schema.py data-pipeline/kanjipipe/db.py data-pipeline/tests/test_db.py
git commit -m "feat(data-pipeline): SQLite schema + init_db for core tables"
```

---

## Task 3: KANJIDIC2 fixture

**Files:**
- Create: `data-pipeline/tests/fixtures/kanjidic2_sample.xml`

This fixture is reused by Tasks 4, 5, and 8. It contains three characters: 山
(grade 1, jōyō), 学 (grade 1, jōyō), and 龠 (grade 9 / 名用, NOT jōyō — used to
test the filter).

- [ ] **Step 1: Create the fixture**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kanjidic2>
<header><file_version>4</file_version><database_version>2025-1</database_version></header>
<character>
  <literal>山</literal>
  <codepoint><cp_value cp_type="ucs">5c71</cp_value></codepoint>
  <radical><rad_value rad_type="classical">46</rad_value></radical>
  <misc>
    <grade>1</grade>
    <stroke_count>3</stroke_count>
    <freq>360</freq>
    <jlpt>4</jlpt>
  </misc>
  <reading_meaning>
    <rmgroup>
      <reading r_type="pinyin">shan1</reading>
      <reading r_type="korean_r">san</reading>
      <reading r_type="korean_h">산</reading>
      <reading r_type="ja_on">サン</reading>
      <reading r_type="ja_kun">やま</reading>
      <meaning>mountain</meaning>
      <meaning m_lang="fr">montagne</meaning>
    </rmgroup>
    <nanori>やの</nanori>
  </reading_meaning>
</character>
<character>
  <literal>学</literal>
  <codepoint><cp_value cp_type="ucs">5b66</cp_value></codepoint>
  <radical><rad_value rad_type="classical">39</rad_value></radical>
  <misc>
    <grade>1</grade>
    <stroke_count>8</stroke_count>
    <freq>63</freq>
    <jlpt>4</jlpt>
  </misc>
  <reading_meaning>
    <rmgroup>
      <reading r_type="pinyin">xue2</reading>
      <reading r_type="korean_h">학</reading>
      <reading r_type="ja_on">ガク</reading>
      <reading r_type="ja_kun">まな.ぶ</reading>
      <meaning>study</meaning>
      <meaning>learning</meaning>
    </rmgroup>
  </reading_meaning>
</character>
<character>
  <literal>龠</literal>
  <codepoint><cp_value cp_type="ucs">9fa0</cp_value></codepoint>
  <radical><rad_value rad_type="classical">214</rad_value></radical>
  <misc>
    <grade>9</grade>
    <stroke_count>17</stroke_count>
  </misc>
  <reading_meaning>
    <rmgroup>
      <reading r_type="ja_on">ヤク</reading>
      <meaning>flute</meaning>
    </rmgroup>
  </reading_meaning>
</character>
</kanjidic2>
```

- [ ] **Step 2: Commit**

```bash
git add data-pipeline/tests/fixtures/kanjidic2_sample.xml
git commit -m "test(data-pipeline): KANJIDIC2 sample fixture"
```

---

## Task 4: KANJIDIC2 parser

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/kanjidic2.py`
- Test: `data-pipeline/tests/test_kanjidic2.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_kanjidic2.py
from pathlib import Path

from kanjipipe.ingest.kanjidic2 import parse_kanjidic2

FIXTURE = Path(__file__).parent / "fixtures" / "kanjidic2_sample.xml"


def test_parses_all_characters():
    kanji = parse_kanjidic2(FIXTURE)
    assert [k.literal for k in kanji] == ["山", "学", "龠"]


def test_extracts_core_fields():
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    assert yama.codepoint == 0x5C71
    assert yama.stroke_count == 3
    assert yama.grade == 1
    assert yama.freq_rank == 360
    assert yama.radical == 46


def test_maps_reading_axes():
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    pairs = {(r.lang_axis, r.value) for r in yama.readings}
    assert ("on", "サン") in pairs
    assert ("kun", "やま") in pairs
    assert ("pinyin", "shan1") in pairs
    assert ("eum", "산") in pairs
    # korean_r (romanized) and nanori are ignored
    assert all(r.lang_axis != "korean_r" for r in yama.readings)


def test_extracts_only_english_meanings_as_glosses():
    gaku = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "学")
    en = [g.text for g in gaku.glosses if g.lang == "en"]
    assert en == ["study", "learning"]
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    # French meaning must NOT become a gloss in this pipeline
    assert all(g.text != "montagne" for g in yama.glosses)


def test_missing_grade_and_freq_become_none():
    flute = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "龠")
    assert flute.grade == 9
    assert flute.freq_rank is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_kanjidic2.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.ingest.kanjidic2'`.

- [ ] **Step 3: Write the parser**

```python
# kanjipipe/ingest/kanjidic2.py
from pathlib import Path

from lxml import etree

from kanjipipe.models import Gloss, Kanji, Reading

_AXIS = {"ja_on": "on", "ja_kun": "kun", "pinyin": "pinyin", "korean_h": "eum"}


def _int_or_none(text: str | None) -> int | None:
    return int(text) if text is not None else None


def parse_kanjidic2(path: str | Path) -> list[Kanji]:
    root = etree.parse(str(path)).getroot()
    result: list[Kanji] = []
    for ch in root.iterfind("character"):
        literal = ch.findtext("literal")

        codepoint = None
        for cp in ch.iterfind("codepoint/cp_value"):
            if cp.get("cp_type") == "ucs":
                codepoint = int(cp.text, 16)

        radical = None
        for rv in ch.iterfind("radical/rad_value"):
            if rv.get("rad_type") == "classical":
                radical = int(rv.text)

        misc = ch.find("misc")
        grade = _int_or_none(misc.findtext("grade"))
        stroke_count = int(misc.findtext("stroke_count"))
        freq_rank = _int_or_none(misc.findtext("freq"))

        readings: list[Reading] = []
        glosses: list[Gloss] = []
        for rm in ch.iterfind("reading_meaning/rmgroup"):
            for r in rm.iterfind("reading"):
                axis = _AXIS.get(r.get("r_type"))
                if axis:
                    readings.append(Reading(lang_axis=axis, value=r.text))
            for m in rm.iterfind("meaning"):
                if m.get("m_lang") is None:  # English meanings carry no m_lang
                    glosses.append(Gloss(lang="en", text=m.text))

        result.append(Kanji(
            literal=literal, codepoint=codepoint, stroke_count=stroke_count,
            grade=grade, freq_rank=freq_rank, radical=radical,
            readings=readings, glosses=glosses,
        ))
    return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_kanjidic2.py -q`
Expected: PASS (5 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/ingest/kanjidic2.py data-pipeline/tests/test_kanjidic2.py
git commit -m "feat(data-pipeline): KANJIDIC2 parser (core fields, readings, EN glosses)"
```

---

## Task 5: Jōyō filter

**Files:**
- Create: `data-pipeline/kanjipipe/filters.py`
- Test: `data-pipeline/tests/test_filters.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_filters.py
from pathlib import Path

from kanjipipe.filters import filter_joyo
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2

FIXTURE = Path(__file__).parent / "fixtures" / "kanjidic2_sample.xml"


def test_keeps_grade_1_to_6_and_8_drops_others():
    kept = filter_joyo(parse_kanjidic2(FIXTURE))
    literals = {k.literal for k in kept}
    assert literals == {"山", "学"}      # grade 1 kept
    assert "龠" not in literals          # grade 9 (名用) dropped
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_filters.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.filters'`.

- [ ] **Step 3: Write the filter**

```python
# kanjipipe/filters.py
from kanjipipe.models import Kanji

JOYO_GRADES = frozenset({1, 2, 3, 4, 5, 6, 8})  # 1-6 = 小, 8 = 中学/常用


def filter_joyo(kanji: list[Kanji]) -> list[Kanji]:
    return [k for k in kanji if k.grade in JOYO_GRADES]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_filters.py -q`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/filters.py data-pipeline/tests/test_filters.py
git commit -m "feat(data-pipeline): jōyō grade filter (1-6, 8)"
```

---

## Task 6: JLPT N5–N1 merge

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/jlpt.py`
- Create: `data-pipeline/tests/fixtures/jlpt_sample.json`
- Test: `data-pipeline/tests/test_jlpt.py`

Background: KANJIDIC2's `<jlpt>` element is the pre-2010 4-level scale and is
intentionally ignored. The modern N5–N1 level comes from a separate mapping
file (`{ "literal": "N5", ... }`).

- [ ] **Step 1: Create the JLPT fixture**

```json
{
  "山": "N5",
  "学": "N5"
}
```

- [ ] **Step 2: Write the failing test**

```python
# tests/test_jlpt.py
from pathlib import Path

from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.models import Kanji

FIXTURE = Path(__file__).parent / "fixtures" / "jlpt_sample.json"


def _kanji(literal):
    return Kanji(literal=literal, codepoint=0, stroke_count=1,
                 grade=1, freq_rank=None, radical=None)


def test_sets_jlpt_level_from_mapping():
    kanji = [_kanji("山"), _kanji("学")]
    merge_jlpt(kanji, FIXTURE)
    assert {k.literal: k.jlpt_level for k in kanji} == {"山": "N5", "学": "N5"}


def test_unmapped_kanji_stays_none():
    kanji = [_kanji("情")]  # not in the fixture
    merge_jlpt(kanji, FIXTURE)
    assert kanji[0].jlpt_level is None
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_jlpt.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.ingest.jlpt'`.

- [ ] **Step 4: Write the merge function**

```python
# kanjipipe/ingest/jlpt.py
import json
from pathlib import Path

from kanjipipe.models import Kanji


def merge_jlpt(kanji: list[Kanji], jlpt_path: str | Path) -> list[Kanji]:
    mapping = json.loads(Path(jlpt_path).read_text(encoding="utf-8"))
    for k in kanji:
        k.jlpt_level = mapping.get(k.literal)
    return kanji
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_jlpt.py -q`
Expected: PASS (2 passed).

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/ingest/jlpt.py data-pipeline/tests/fixtures/jlpt_sample.json data-pipeline/tests/test_jlpt.py
git commit -m "feat(data-pipeline): merge modern JLPT N5-N1 levels (overrides old scale)"
```

---

## Task 7: Loader (write to SQLite)

**Files:**
- Create: `data-pipeline/kanjipipe/loader.py`
- Test: `data-pipeline/tests/test_loader.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_loader.py
from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji
from kanjipipe.models import Gloss, Kanji, Reading


def _yama():
    return Kanji(
        literal="山", codepoint=0x5C71, stroke_count=3, grade=1,
        freq_rank=360, radical=46, jlpt_level="N5",
        readings=[Reading("on", "サン"), Reading("kun", "やま"),
                  Reading("pinyin", "shan1"), Reading("eum", "산")],
        glosses=[Gloss("en", "mountain")],
    )


def test_inserts_kanji_with_readings_and_glosses():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])

    row = conn.execute(
        "SELECT literal, stroke_count, grade, jlpt_level, freq_rank, radical "
        "FROM kanji").fetchone()
    assert row == ("山", 3, 1, "N5", 360, 46)

    reading_count = conn.execute(
        "SELECT COUNT(*) FROM reading").fetchone()[0]
    assert reading_count == 4

    gloss = conn.execute(
        "SELECT lang, text FROM gloss").fetchone()
    assert gloss == ("en", "mountain")


def test_foreign_keys_link_children_to_parent():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    linked = conn.execute(
        "SELECT COUNT(*) FROM reading r JOIN kanji k ON r.kanji_id = k.id "
        "WHERE k.literal = '山'").fetchone()[0]
    assert linked == 4
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.loader'`.

- [ ] **Step 3: Write the loader**

```python
# kanjipipe/loader.py
import sqlite3

from kanjipipe.models import Kanji


def load_kanji(conn: sqlite3.Connection, kanji: list[Kanji]) -> None:
    for k in kanji:
        cur = conn.execute(
            "INSERT INTO kanji "
            "(literal, codepoint, stroke_count, grade, jlpt_level, freq_rank, radical) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (k.literal, k.codepoint, k.stroke_count, k.grade,
             k.jlpt_level, k.freq_rank, k.radical),
        )
        kanji_id = cur.lastrowid
        for r in k.readings:
            conn.execute(
                "INSERT INTO reading (kanji_id, lang_axis, value, is_common) "
                "VALUES (?, ?, ?, ?)",
                (kanji_id, r.lang_axis, r.value, 1 if r.is_common else 0),
            )
        for g in k.glosses:
            conn.execute(
                "INSERT INTO gloss (kanji_id, lang, text) VALUES (?, ?, ?)",
                (kanji_id, g.lang, g.text),
            )
    conn.commit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/loader.py data-pipeline/tests/test_loader.py
git commit -m "feat(data-pipeline): loader writes kanji/reading/gloss to SQLite"
```

---

## Task 8: Validation & coverage gates

**Files:**
- Create: `data-pipeline/kanjipipe/validate.py`
- Test: `data-pipeline/tests/test_validate.py`

The core gate (this plan): every kanji must have a non-null grade, ≥1 reading,
and ≥1 English gloss, and at least one kanji must be loaded. (The 4-language
gloss + stroke-order gates arrive with their follow-on plans.)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_validate.py
import pytest

from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji
from kanjipipe.models import Gloss, Kanji, Reading
from kanjipipe.validate import assert_core_gates, coverage_report


def _good():
    return Kanji(literal="山", codepoint=0x5C71, stroke_count=3, grade=1,
                 freq_rank=360, radical=46, jlpt_level="N5",
                 readings=[Reading("on", "サン")],
                 glosses=[Gloss("en", "mountain")])


def test_coverage_report_counts_gaps():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    report = coverage_report(conn)
    assert report["total"] == 1
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0
    assert report["missing_grade"] == 0


def test_assert_core_gates_passes_on_complete_data():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    assert assert_core_gates(conn)["total"] == 1


def test_assert_core_gates_fails_when_english_missing():
    conn = init_db(":memory:")
    no_gloss = _good()
    no_gloss.glosses = []
    load_kanji(conn, [no_gloss])
    with pytest.raises(ValueError, match="missing EN meaning"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_on_empty_db():
    conn = init_db(":memory:")
    with pytest.raises(ValueError, match="no kanji loaded"):
        assert_core_gates(conn)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.validate'`.

- [ ] **Step 3: Write the validator**

```python
# kanjipipe/validate.py
import sqlite3


def coverage_report(conn: sqlite3.Connection) -> dict[str, int]:
    def scalar(sql: str) -> int:
        return conn.execute(sql).fetchone()[0]

    return {
        "total": scalar("SELECT COUNT(*) FROM kanji"),
        "missing_reading": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM reading r WHERE r.kanji_id = k.id)"),
        "missing_en": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM gloss g WHERE g.kanji_id = k.id AND g.lang = 'en')"),
        "missing_grade": scalar(
            "SELECT COUNT(*) FROM kanji WHERE grade IS NULL"),
    }


def assert_core_gates(conn: sqlite3.Connection) -> dict[str, int]:
    report = coverage_report(conn)
    problems: list[str] = []
    if report["total"] == 0:
        problems.append("no kanji loaded")
    if report["missing_reading"]:
        problems.append(f"{report['missing_reading']} kanji missing readings")
    if report["missing_en"]:
        problems.append(f"{report['missing_en']} kanji missing EN meaning")
    if report["missing_grade"]:
        problems.append(f"{report['missing_grade']} kanji missing grade")
    if problems:
        raise ValueError("coverage gate failed: " + "; ".join(problems))
    return report
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/validate.py data-pipeline/tests/test_validate.py
git commit -m "feat(data-pipeline): coverage report + core build gates"
```

---

## Task 9: Orchestrator + fetch script

**Files:**
- Create: `data-pipeline/kanjipipe/build_db.py`
- Create: `data-pipeline/scripts/fetch_sources.sh`
- Test: `data-pipeline/tests/test_build_db.py`

- [ ] **Step 1: Write the failing integration test**

```python
# tests/test_build_db.py
from pathlib import Path

from kanjipipe.build_db import build

FIX = Path(__file__).parent / "fixtures"


def test_build_produces_sqlite_with_only_joyo(tmp_path):
    out = tmp_path / "kanji.sqlite"
    report = build(
        kanjidic2_path=FIX / "kanjidic2_sample.xml",
        jlpt_path=FIX / "jlpt_sample.json",
        out_path=str(out),
    )
    assert out.exists()
    assert report["total"] == 2          # 山, 学 — 龠 filtered out
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0

    import sqlite3
    conn = sqlite3.connect(out)
    literals = {r[0] for r in conn.execute("SELECT literal FROM kanji")}
    assert literals == {"山", "学"}
    jlpt = dict(conn.execute("SELECT literal, jlpt_level FROM kanji"))
    assert jlpt == {"山": "N5", "学": "N5"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'kanjipipe.build_db'`.

- [ ] **Step 3: Write the orchestrator**

```python
# kanjipipe/build_db.py
import argparse
import os
from pathlib import Path

from kanjipipe.db import init_db
from kanjipipe.filters import filter_joyo
from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2
from kanjipipe.loader import load_kanji
from kanjipipe.validate import assert_core_gates


def build(kanjidic2_path, jlpt_path, out_path: str) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    load_kanji(conn, kanji)
    report = assert_core_gates(conn)
    conn.close()
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Build kanji.sqlite")
    parser.add_argument("--kanjidic2", default="sources/kanjidic2.xml")
    parser.add_argument("--jlpt", default="sources/jlpt.json")
    parser.add_argument("--out", default="out/kanji.sqlite")
    args = parser.parse_args()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    report = build(args.kanjidic2, args.jlpt, args.out)
    print(f"built {args.out}: {report}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: PASS (1 passed).

- [ ] **Step 5: Write the fetch script**

```bash
# scripts/fetch_sources.sh
#!/usr/bin/env bash
# Download raw open datasets into data-pipeline/sources/ (gitignored).
# KANJIDIC2: EDRDG, CC BY-SA 4.0. JLPT N5-N1 list: bundled separately.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources

echo "Fetching KANJIDIC2..."
curl -fsSL "http://www.edrdg.org/kanjidic/kanjidic2.xml.gz" -o sources/kanjidic2.xml.gz
gunzip -f sources/kanjidic2.xml.gz   # -> sources/kanjidic2.xml

# NOTE: sources/jlpt.json (modern N5-N1 mapping) is provided manually — see
# docs. KANJIDIC2's own <jlpt> is the obsolete 4-level scale and is not used.
echo "Done. Place the N5-N1 mapping at sources/jlpt.json before building."
```

Then make it executable:
```bash
chmod +x data-pipeline/scripts/fetch_sources.sh
```

- [ ] **Step 6: Run the full test suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: PASS (all tasks' tests green).

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/build_db.py data-pipeline/scripts/fetch_sources.sh data-pipeline/tests/test_build_db.py
git commit -m "feat(data-pipeline): build_db orchestrator + fetch_sources script"
```

---

## Self-Review notes (addressed)

- **Spec coverage (this plan's slice):** kanji core fields, on/kun/pinyin/Korean音
  readings, English gloss, jōyō filter, JLPT N5–N1 merge with old-scale override,
  SQLite emission, and a coverage gate are each implemented by a task above.
  Stroke order, words, sentences, relations, Korean 훈, and LLM gap-fill are
  explicitly out of scope here and tracked as follow-on plans.
- **Coverage-gate scope:** the spec's "4-language gloss + stroke-order" hard gate
  is intentionally narrowed to "grade + ≥1 reading + EN gloss" for this plan,
  since the data feeding the other gates lands in later plans. This is called out
  in Task 8 so it isn't mistaken for the final gate.
- **Type consistency:** `Kanji`/`Reading`/`Gloss` field names and the
  `coverage_report` keys (`total`, `missing_reading`, `missing_en`,
  `missing_grade`) are used identically across Tasks 1, 7, 8, and 9.
- **No placeholders:** every code/test step contains complete content.

## Follow-on plans (not in this plan)

1. KanjiVG stroke-order ingester (+ `stroke_order` table + gate).
2. JMdict words (`word`, `word_kanji`, `word_gloss`).
3. Tatoeba sentences (`sentence`, `sentence_translation`).
4. WordNet + JMdict ant/xref relations (`relation`).
5. Korean 훈음 dataset → KO gloss (훈+음), 新字体↔정자체 via Unihan variants.
6. LLM (Claude) gap-fill for ZH/JA/KO native glosses + relation curation, with
   `source` provenance flags and the final 4-language coverage gate.

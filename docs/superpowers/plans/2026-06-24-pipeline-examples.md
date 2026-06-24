# Data Pipeline — Example Sentences (Tatoeba) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach a few short Japanese example sentences (with en/ko/zh translations) to each jōyō kanji they contain, for the study card's example section.

**Architecture:** Add `sentence`/`sentence_translation`/`sentence_kanji` tables. A `parse_tatoeba` ingester yields Japanese sentences + en/ko/zh translations from Tatoeba's `sentences.csv` + `links.csv`; `load_sentences` attaches up to `per_kanji_cap` (default 3) of the shortest sentences to each contained jōyō kanji; the orchestrator gains `sentences_path`/`links_path`; an informational non-gating `kanji_without_sentences` report field is added. Additive — core gates unchanged.

**Tech Stack:** Python 3.11+ (csv + lxml already present), sqlite3, pytest. Commands from repo root; venv at `data-pipeline/.venv`; `git` from repo root.

---

## File Structure (this slice)

```
data-pipeline/
├── kanjipipe/
│   ├── models.py             # + Sentence dataclass (modify)
│   ├── schema.py             # + sentence/sentence_translation/sentence_kanji (modify)
│   ├── ingest/tatoeba.py     # parse_tatoeba (new)
│   ├── loader.py             # + load_sentences (modify)
│   ├── validate.py           # + kanji_without_sentences report (modify)
│   └── build_db.py           # + sentences_path/links_path stage (modify)
├── scripts/fetch_sources.sh  # + Tatoeba fetch (modify)
└── tests/
    ├── fixtures/sentences_sample.csv   # (new, tab-separated)
    ├── fixtures/links_sample.csv       # (new, tab-separated)
    ├── test_tatoeba.py                 # (new)
    ├── test_loader.py                  # + sentence cases (modify)
    ├── test_validate.py                # + report field (modify)
    ├── test_db.py                      # + tables (modify)
    └── test_build_db.py                # + tatoeba paths + sentence assert (modify)
```

---

## Task 1: Schema + Sentence model + fixtures

**Files:**
- Modify: `data-pipeline/kanjipipe/models.py`
- Modify: `data-pipeline/kanjipipe/schema.py`
- Modify: `data-pipeline/tests/test_db.py`
- Create: `data-pipeline/tests/fixtures/sentences_sample.csv`
- Create: `data-pipeline/tests/fixtures/links_sample.csv`

- [ ] **Step 1: Add the failing table-exists assertion**

In `data-pipeline/tests/test_db.py`, extend the table-set assertion:

```python
    assert {"kanji", "reading", "gloss", "stroke_order",
            "word", "word_kanji", "word_gloss",
            "sentence", "sentence_translation", "sentence_kanji"} <= tables
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: FAIL — sentence tables missing.

- [ ] **Step 3: Add the tables to the schema**

In `data-pipeline/kanjipipe/schema.py`, append to the `DDL` string (before the
closing `"""`):

```sql
CREATE TABLE sentence (
    id      INTEGER PRIMARY KEY,
    text_ja TEXT NOT NULL
);

CREATE TABLE sentence_translation (
    id          INTEGER PRIMARY KEY,
    sentence_id INTEGER NOT NULL REFERENCES sentence(id),
    lang        TEXT NOT NULL,
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

- [ ] **Step 4: Add the Sentence model**

In `data-pipeline/kanjipipe/models.py`, append:

```python
@dataclass
class Sentence:
    ja_text: str
    translations: dict[str, str] = field(default_factory=dict)
```

- [ ] **Step 5: Create the Tatoeba fixtures (TAB-separated)**

Create `data-pipeline/tests/fixtures/sentences_sample.csv` — columns
`id<TAB>lang<TAB>text`, one row per line, real tab characters:

```
1	jpn	山が高い。
2	eng	The mountain is high.
3	kor	산이 높다.
6	cmn	这是山。
4	jpn	学校に行く。
5	eng	I go to school.
7	fra	La montagne est haute.
```

Create `data-pipeline/tests/fixtures/links_sample.csv` — columns
`sentence_id<TAB>translation_id`, real tabs:

```
1	2
1	3
1	6
4	5
```

- [ ] **Step 6: Run the table test to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_db.py -q`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/models.py data-pipeline/kanjipipe/schema.py data-pipeline/tests/test_db.py data-pipeline/tests/fixtures/sentences_sample.csv data-pipeline/tests/fixtures/links_sample.csv
git commit -m "feat(data-pipeline): sentence tables + Sentence model + Tatoeba fixtures"
```

---

## Task 2: Tatoeba parser (TDD)

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/tatoeba.py`
- Create: `data-pipeline/tests/test_tatoeba.py`

- [ ] **Step 1: Write the failing test**

Create `data-pipeline/tests/test_tatoeba.py`:

```python
# tests/test_tatoeba.py
from pathlib import Path

from kanjipipe.ingest.tatoeba import parse_tatoeba

FIX = Path(__file__).parent / "fixtures"


def _parse():
    return parse_tatoeba(FIX / "sentences_sample.csv", FIX / "links_sample.csv")


def test_collects_japanese_sentences_with_translations():
    sentences = _parse()
    by_text = {s.ja_text: s.translations for s in sentences}
    assert by_text["山が高い。"] == {
        "en": "The mountain is high.",
        "ko": "산이 높다.",
        "zh": "这是山。",
    }


def test_sentence_with_only_english_keeps_english_only():
    sentences = _parse()
    gakkou = next(s for s in sentences if s.ja_text == "学校に行く。")
    assert gakkou.translations == {"en": "I go to school."}


def test_non_japanese_sentences_are_not_returned_as_entries():
    # The French sentence (id 7) is never a returned Sentence; only jpn entries are.
    sentences = _parse()
    assert all("montagne" not in s.ja_text.lower() for s in sentences)
    assert len(sentences) == 2
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_tatoeba.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'kanjipipe.ingest.tatoeba'`.

- [ ] **Step 3: Write the parser**

Create `data-pipeline/kanjipipe/ingest/tatoeba.py`:

```python
"""Parse Tatoeba sentences + links into Japanese sentences with translations."""
import csv
from pathlib import Path

from kanjipipe.models import Sentence

# Tatoeba lang code -> our translation lang key.
_LANG_MAP = {"eng": "en", "kor": "ko", "cmn": "zh"}
_KEEP_LANGS = {"jpn", *_LANG_MAP}


def parse_tatoeba(sentences_path: str | Path, links_path: str | Path) -> list[Sentence]:
    # 1. Keep only sentences in the languages we care about.
    by_id: dict[int, tuple[str, str]] = {}
    with open(sentences_path, encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 3:
                continue
            lang = row[1]
            if lang in _KEEP_LANGS:
                by_id[int(row[0])] = (lang, row[2])

    # 2. Undirected adjacency over translation links.
    adjacency: dict[int, set[int]] = {}
    with open(links_path, encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 2:
                continue
            a, b = int(row[0]), int(row[1])
            adjacency.setdefault(a, set()).add(b)
            adjacency.setdefault(b, set()).add(a)

    # 3. For each Japanese sentence, gather one translation per target language.
    sentences: list[Sentence] = []
    for sid, (lang, text) in by_id.items():
        if lang != "jpn":
            continue
        translations: dict[str, str] = {}
        for neighbour in adjacency.get(sid, ()):
            entry = by_id.get(neighbour)
            if entry is None:
                continue
            key = _LANG_MAP.get(entry[0])
            if key and key not in translations:
                translations[key] = entry[1]
        if translations:
            sentences.append(Sentence(ja_text=text, translations=translations))
    return sentences
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_tatoeba.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/ingest/tatoeba.py data-pipeline/tests/test_tatoeba.py
git commit -m "feat(data-pipeline): Tatoeba parser (jpn sentences + en/ko/zh translations)"
```

---

## Task 3: load_sentences with per-kanji cap (TDD)

**Files:**
- Modify: `data-pipeline/kanjipipe/loader.py`
- Modify: `data-pipeline/tests/test_loader.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_loader.py`:

```python
from kanjipipe.loader import load_sentences
from kanjipipe.models import Sentence


def test_load_sentences_caps_per_kanji_and_prefers_short():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山

    load_sentences(conn, [
        Sentence(ja_text="山。", translations={"en": "Mountain."}),          # shortest
        Sentence(ja_text="山が高い。", translations={"en": "The mountain is high."}),
        Sentence(ja_text="あの山はとても高いです。", translations={"en": "long"}),
    ], per_kanji_cap=1)

    rows = conn.execute(
        "SELECT s.text_ja FROM sentence s "
        "JOIN sentence_kanji sk ON sk.sentence_id = s.id "
        "JOIN kanji k ON sk.kanji_id = k.id WHERE k.literal = '山'").fetchall()
    assert rows == [("山。",)]                                   # only the shortest, cap honored
    assert conn.execute("SELECT COUNT(*) FROM sentence").fetchone()[0] == 1
    tr = conn.execute("SELECT lang, text FROM sentence_translation").fetchone()
    assert tr == ("en", "Mountain.")


def test_load_sentences_skips_sentence_without_joyo_kanji():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_sentences(conn, [Sentence(ja_text="これはペンです。", translations={"en": "This is a pen."})])
    assert conn.execute("SELECT COUNT(*) FROM sentence").fetchone()[0] == 0
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: FAIL — `cannot import name 'load_sentences'`.

- [ ] **Step 3: Implement the loader**

Append to `data-pipeline/kanjipipe/loader.py`:

```python
def load_sentences(
    conn: sqlite3.Connection,
    sentences: list["Sentence"],
    per_kanji_cap: int = 3,
) -> None:
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    counts: dict[int, int] = {}
    for sentence in sorted(sentences, key=lambda s: len(s.ja_text)):
        needed: list[int] = []
        seen: set[int] = set()
        for char in sentence.ja_text:
            kanji_id = kanji_id_by_literal.get(char)
            if kanji_id is None or kanji_id in seen:
                continue
            seen.add(kanji_id)
            if counts.get(kanji_id, 0) < per_kanji_cap:
                needed.append(kanji_id)
        if not needed:
            continue
        cur = conn.execute(
            "INSERT INTO sentence (text_ja) VALUES (?)", (sentence.ja_text,))
        sentence_id = cur.lastrowid
        for lang, text in sentence.translations.items():
            conn.execute(
                "INSERT INTO sentence_translation (sentence_id, lang, text) "
                "VALUES (?, ?, ?)",
                (sentence_id, lang, text),
            )
        for kanji_id in needed:
            conn.execute(
                "INSERT INTO sentence_kanji (sentence_id, kanji_id) VALUES (?, ?)",
                (sentence_id, kanji_id),
            )
            counts[kanji_id] = counts.get(kanji_id, 0) + 1
    conn.commit()
```

Update the models import at the top of `loader.py` to include `Sentence`:
```python
from kanjipipe.models import Kanji, Sentence, Word
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/loader.py data-pipeline/tests/test_loader.py
git commit -m "feat(data-pipeline): load_sentences with per-kanji cap, shortest-first"
```

---

## Task 4: kanji_without_sentences report (TDD, non-gating)

**Files:**
- Modify: `data-pipeline/kanjipipe/validate.py`
- Modify: `data-pipeline/tests/test_validate.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_validate.py`:

```python
def test_coverage_report_counts_kanji_without_sentences():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                 # 山
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert coverage_report(conn)["kanji_without_sentences"] == 1


def test_gates_do_not_fail_on_missing_sentences():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert assert_core_gates(conn)["kanji_without_sentences"] == 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: FAIL — no `kanji_without_sentences` key.

- [ ] **Step 3: Add the report field (not the gate)**

In `data-pipeline/kanjipipe/validate.py`, add to the dict returned by
`coverage_report` (after `kanji_without_words`):

```python
        "kanji_without_sentences": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM sentence_kanji sk WHERE sk.kanji_id = k.id)"),
```

Do **not** modify `assert_core_gates`.

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/validate.py data-pipeline/tests/test_validate.py
git commit -m "feat(data-pipeline): report kanji_without_sentences (non-gating)"
```

---

## Task 5: Orchestrator integration + fetch

**Files:**
- Modify: `data-pipeline/kanjipipe/build_db.py`
- Modify: `data-pipeline/tests/test_build_db.py`
- Modify: `data-pipeline/scripts/fetch_sources.sh`

- [ ] **Step 1: Update the integration test (failing)**

In `data-pipeline/tests/test_build_db.py`, update the `build(...)` call to pass
the two Tatoeba paths and add a sentence assertion. The test becomes:

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
        sentences_path=FIX / "sentences_sample.csv",
        links_path=FIX / "links_sample.csv",
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
        yama_words = conn.execute(
            "SELECT w.surface FROM word w "
            "JOIN word_kanji wk ON wk.word_id = w.id "
            "JOIN kanji k ON wk.kanji_id = k.id "
            "WHERE k.literal = '山' ORDER BY w.surface").fetchall()
        assert ("山",) in yama_words
        # 山 has an example sentence with an English translation
        yama_sentence = conn.execute(
            "SELECT s.text_ja FROM sentence s "
            "JOIN sentence_kanji sk ON sk.sentence_id = s.id "
            "JOIN kanji k ON sk.kanji_id = k.id "
            "WHERE k.literal = '山'").fetchone()
        assert yama_sentence is not None
        en = conn.execute(
            "SELECT st.text FROM sentence_translation st "
            "JOIN sentence_kanji sk ON sk.sentence_id = st.sentence_id "
            "JOIN kanji k ON sk.kanji_id = k.id "
            "WHERE k.literal = '山' AND st.lang = 'en'").fetchone()
        assert en is not None
    conn.close()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: FAIL — `build()` got an unexpected keyword argument `sentences_path`.

- [ ] **Step 3: Wire Tatoeba into the orchestrator**

In `data-pipeline/kanjipipe/build_db.py`:

(a) add the import:
```python
from kanjipipe.ingest.tatoeba import parse_tatoeba
```
and extend the loader import to include `load_sentences`:
```python
from kanjipipe.loader import load_kanji, load_sentences, load_stroke_order, load_words
```

(b) replace the `build` function with:
```python
def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    jmdict_path: str | Path,
    sentences_path: str | Path,
    links_path: str | Path,
    out_path: str,
) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)
    strokes = parse_kanjivg(kanjivg_path)
    words = parse_jmdict(jmdict_path)
    sentences = parse_tatoeba(sentences_path, links_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    try:
        load_kanji(conn, kanji)
        load_stroke_order(conn, strokes)
        load_words(conn, words)
        load_sentences(conn, sentences)
        report = assert_core_gates(conn)  # raises if a gate fails
    finally:
        conn.close()  # always release the handle, even on gate failure
    return report
```

(c) in `main()`, add the two arguments and pass them:
```python
    parser.add_argument("--sentences", default="sources/sentences.csv")
    parser.add_argument("--links", default="sources/links.csv")
```
and update the call to:
```python
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.jmdict,
                   args.sentences, args.links, args.out)
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: PASS.

- [ ] **Step 5: Run the FULL suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: all tests pass.

- [ ] **Step 6: Add Tatoeba to the fetch script**

In `data-pipeline/scripts/fetch_sources.sh`, before the final `echo "Done..."`
line, add:

```bash
echo "Fetching Tatoeba sentences + links..."
curl -fsSL "https://downloads.tatoeba.org/exports/sentences.tar.bz2" -o sources/sentences.tar.bz2
curl -fsSL "https://downloads.tatoeba.org/exports/links.tar.bz2" -o sources/links.tar.bz2
tar -xjf sources/sentences.tar.bz2 -C sources   # -> sources/sentences.csv
tar -xjf sources/links.tar.bz2 -C sources       # -> sources/links.csv
```

> Tatoeba dumps (CC BY 2.0 FR) are large; the parser keeps only jpn/eng/kor/cmn
> rows, so memory stays bounded despite the all-languages file.

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/build_db.py data-pipeline/tests/test_build_db.py data-pipeline/scripts/fetch_sources.sh
git commit -m "feat(data-pipeline): build_db loads Tatoeba example sentences + fetch step"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** sentence tables (spec §4) → Task 1; `parse_tatoeba` (§5) →
  Task 2; `load_sentences` cap + shortest-first (§5/§6) → Task 3;
  `kanji_without_sentences` non-gating report (§5) → Task 4; orchestrator
  `sentences_path`/`links_path` + fetch (§5/§6) → Task 5; tests (§7) across
  Tasks 2–5.
- **Breaking change handled:** `build()` gains required `sentences_path` +
  `links_path`; the only caller in tests is updated (Task 5 Step 1) and `main()`
  passes the new args. Regenerating the real bundled DB now also needs
  `sources/sentences.csv` + `sources/links.csv` (fetch step adds them).
- **Non-gating confirmed:** `kanji_without_sentences` is report-only;
  `assert_core_gates` unchanged.
- **Type consistency:** `parse_tatoeba(sentences_path, links_path) -> list[Sentence]`,
  `Sentence{ja_text, translations}`, `load_sentences(conn, sentences, per_kanji_cap=3)`,
  and the `kanji_without_sentences` report key are used identically across tasks.
- **Memory:** the parser filters `sentences.csv` to jpn/eng/kor/cmn while reading,
  so the all-languages dump does not all stay resident.

## Follow-on (not in this plan)

WordNet synonym/antonym relations, Korean 훈, LLM 4-language glosses, and the
study-card UI that displays sentences.

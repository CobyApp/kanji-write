# Data Pipeline — LLM 4-Language Glosses — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load LLM-generated native glosses (Korean 훈음, Japanese, Chinese) for jōyō kanji into the `gloss` table with `source='llm'`. Tasks 1–4 build the ingester (TDD); the generation run (filling `sources/llm_glosses.jsonl`) is a separate controller step after this plan.

**Architecture:** Add a `gloss.source` column. `parse_llm_glosses` reads a JSONL of `{literal, ko, ja, zh}`; `load_llm_glosses` inserts ko/ja/zh into `gloss` (source='llm') for stored kanji; the orchestrator loads them via an optional `llm_glosses_path`; a non-gating `kanji_without_native_gloss` report field is added.

**Tech Stack:** Python 3.11+ (json + sqlite3 stdlib), pytest. Commands from repo root; venv at `data-pipeline/.venv`; `git` from repo root.

---

## File Structure (this slice)

```
data-pipeline/
├── kanjipipe/
│   ├── models.py               # + LlmGloss dataclass (modify)
│   ├── schema.py               # gloss gains `source` column (modify)
│   ├── ingest/llm_glosses.py   # parse_llm_glosses (new)
│   ├── loader.py               # + load_llm_glosses (modify)
│   ├── validate.py             # + kanji_without_native_gloss report (modify)
│   └── build_db.py             # + optional llm_glosses_path stage (modify)
└── tests/
    ├── fixtures/llm_glosses_sample.jsonl   # (new)
    ├── test_llm_glosses.py                 # (new)
    ├── test_loader.py                      # + llm gloss cases (modify)
    ├── test_validate.py                    # + report field (modify)
    └── test_build_db.py                    # + llm_glosses_path + ko gloss assert (modify)
```

---

## Task 1: LlmGloss model + parser (TDD)

**Files:**
- Modify: `data-pipeline/kanjipipe/models.py`
- Create: `data-pipeline/kanjipipe/ingest/llm_glosses.py`
- Create: `data-pipeline/tests/fixtures/llm_glosses_sample.jsonl`
- Create: `data-pipeline/tests/test_llm_glosses.py`

- [ ] **Step 1: Add the model**

In `data-pipeline/kanjipipe/models.py`, append:

```python
@dataclass
class LlmGloss:
    literal: str
    ko: str | None = None
    ja: str | None = None
    zh: str | None = None
```

- [ ] **Step 2: Create the JSONL fixture**

Create `data-pipeline/tests/fixtures/llm_glosses_sample.jsonl` (one JSON per line;
the 3rd line has a missing field, the 4th is blank):

```
{"literal": "山", "ko": "메 산", "ja": "やま。地面が高く盛り上がった所。", "zh": "山。"}
{"literal": "学", "ko": "배울 학", "ja": "まなぶ。", "zh": "学习。"}
{"literal": "未", "ko": "아닐 미", "zh": "未。"}

```

- [ ] **Step 3: Write the failing test**

Create `data-pipeline/tests/test_llm_glosses.py`:

```python
# tests/test_llm_glosses.py
from pathlib import Path

from kanjipipe.ingest.llm_glosses import parse_llm_glosses

FIXTURE = Path(__file__).parent / "fixtures" / "llm_glosses_sample.jsonl"


def test_parses_jsonl_entries_skipping_blank_lines():
    entries = parse_llm_glosses(FIXTURE)
    assert [e.literal for e in entries] == ["山", "学", "未"]  # blank line skipped


def test_extracts_all_three_languages():
    yama = next(e for e in parse_llm_glosses(FIXTURE) if e.literal == "山")
    assert yama.ko == "메 산"
    assert yama.ja == "やま。地面が高く盛り上がった所。"
    assert yama.zh == "山。"


def test_missing_field_becomes_none():
    mi = next(e for e in parse_llm_glosses(FIXTURE) if e.literal == "未")
    assert mi.ko == "아닐 미"
    assert mi.ja is None      # absent in the fixture line
    assert mi.zh == "未。"
```

- [ ] **Step 4: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_llm_glosses.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'kanjipipe.ingest.llm_glosses'`.

- [ ] **Step 5: Write the parser**

Create `data-pipeline/kanjipipe/ingest/llm_glosses.py`:

```python
"""Parse the LLM-generated native-gloss JSONL ({literal, ko, ja, zh} per line)."""
import json
from pathlib import Path

from kanjipipe.models import LlmGloss


def parse_llm_glosses(path: str | Path) -> list[LlmGloss]:
    entries: list[LlmGloss] = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            entries.append(LlmGloss(
                literal=obj["literal"],
                ko=obj.get("ko"),
                ja=obj.get("ja"),
                zh=obj.get("zh"),
            ))
    return entries
```

- [ ] **Step 6: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_llm_glosses.py -q`
Expected: PASS (3 passed).

- [ ] **Step 7: Commit**

```bash
git add data-pipeline/kanjipipe/models.py data-pipeline/kanjipipe/ingest/llm_glosses.py data-pipeline/tests/fixtures/llm_glosses_sample.jsonl data-pipeline/tests/test_llm_glosses.py
git commit -m "feat(data-pipeline): LlmGloss model + JSONL parser"
```

---

## Task 2: gloss.source column + load_llm_glosses (TDD)

**Files:**
- Modify: `data-pipeline/kanjipipe/schema.py`
- Modify: `data-pipeline/kanjipipe/loader.py`
- Modify: `data-pipeline/tests/test_loader.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_loader.py`:

```python
from kanjipipe.loader import load_llm_glosses
from kanjipipe.models import LlmGloss


def test_load_llm_glosses_inserts_native_glosses_with_source():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山, with an EN gloss (source NULL)

    load_llm_glosses(conn, [
        LlmGloss(literal="山", ko="메 산", ja="やま。", zh="山。"),
        LlmGloss(literal="未", ko="아닐 미"),  # not a stored kanji → skipped
    ])

    rows = conn.execute(
        "SELECT g.lang, g.text, g.source FROM gloss g "
        "JOIN kanji k ON g.kanji_id = k.id "
        "WHERE k.literal = '山' AND g.source = 'llm' ORDER BY g.lang").fetchall()
    assert rows == [("ja", "やま。", "llm"), ("ko", "메 산", "llm"), ("zh", "山。", "llm")]

    # the original English gloss is untouched (source NULL)
    en = conn.execute(
        "SELECT text, source FROM gloss g JOIN kanji k ON g.kanji_id = k.id "
        "WHERE k.literal = '山' AND g.lang = 'en'").fetchone()
    assert en == ("mountain", None)

    # the unstored literal produced no rows
    assert conn.execute("SELECT COUNT(*) FROM gloss WHERE lang='ko'").fetchone()[0] == 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: FAIL — `cannot import name 'load_llm_glosses'` (and/or no `source` column).

- [ ] **Step 3: Add the `source` column**

In `data-pipeline/kanjipipe/schema.py`, change the `gloss` table definition to
add a nullable `source` column:

```sql
CREATE TABLE gloss (
    id       INTEGER PRIMARY KEY,
    kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    lang     TEXT    NOT NULL,    -- 'ko' | 'ja' | 'zh' | 'en'
    text     TEXT    NOT NULL,
    source   TEXT                 -- NULL = KANJIDIC2 (English); 'llm' = generated native gloss
);
```

(The English-gloss insert in `load_kanji` lists `(kanji_id, lang, text)` and
leaves `source` NULL — no change needed there.)

- [ ] **Step 4: Implement the loader**

Append to `data-pipeline/kanjipipe/loader.py`:

```python
def load_llm_glosses(conn: sqlite3.Connection, entries: list["LlmGloss"]) -> None:
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    for entry in entries:
        kanji_id = kanji_id_by_literal.get(entry.literal)
        if kanji_id is None:
            continue
        for lang, text in (("ko", entry.ko), ("ja", entry.ja), ("zh", entry.zh)):
            if text:
                conn.execute(
                    "INSERT INTO gloss (kanji_id, lang, text, source) "
                    "VALUES (?, ?, ?, 'llm')",
                    (kanji_id, lang, text),
                )
    conn.commit()
```

Update the models import at the top of `loader.py` to include `LlmGloss`:
```python
from kanjipipe.models import Kanji, LlmGloss, Relation, Sentence, Word
```

- [ ] **Step 5: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_loader.py -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/schema.py data-pipeline/kanjipipe/loader.py data-pipeline/tests/test_loader.py
git commit -m "feat(data-pipeline): gloss.source column + load_llm_glosses (source='llm')"
```

---

## Task 3: kanji_without_native_gloss report (TDD, non-gating)

**Files:**
- Modify: `data-pipeline/kanjipipe/validate.py`
- Modify: `data-pipeline/tests/test_validate.py`

- [ ] **Step 1: Write the failing test**

Append to `data-pipeline/tests/test_validate.py` (add `load_llm_glosses` +
`LlmGloss` to the existing imports):

```python
def test_coverage_report_counts_kanji_without_native_gloss():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                 # 山, English gloss only
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert coverage_report(conn)["kanji_without_native_gloss"] == 1


def test_native_gloss_present_drops_the_count():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
    assert assert_core_gates(conn)["kanji_without_native_gloss"] == 0
```

Update the import lines at the top of `test_validate.py`:
```python
from kanjipipe.loader import load_kanji, load_llm_glosses, load_stroke_order, load_words
from kanjipipe.models import Gloss, Kanji, LlmGloss, Reading, Word
```
(keep whatever symbols are already imported; just add `load_llm_glosses` and `LlmGloss`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: FAIL — no `kanji_without_native_gloss` key.

- [ ] **Step 3: Add the report field (not the gate)**

In `data-pipeline/kanjipipe/validate.py`, add to the dict returned by
`coverage_report` (after `kanji_without_sentences`):

```python
        "kanji_without_native_gloss": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM gloss g WHERE g.kanji_id = k.id AND g.lang = 'ko')"),
```

Do **not** modify `assert_core_gates`.

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/validate.py data-pipeline/tests/test_validate.py
git commit -m "feat(data-pipeline): report kanji_without_native_gloss (non-gating)"
```

---

## Task 4: Orchestrator integration (optional path)

**Files:**
- Modify: `data-pipeline/kanjipipe/build_db.py`
- Modify: `data-pipeline/tests/test_build_db.py`

- [ ] **Step 1: Add the failing assertion**

In `data-pipeline/tests/test_build_db.py`, add `llm_glosses_path` to the
`build(...)` call:

```python
        llm_glosses_path=FIX / "llm_glosses_sample.jsonl",
```
(add it as a keyword argument before `out_path=...`), and inside the
`with sqlite3.connect(out) as conn:` block add:

```python
        # 山 native Korean gloss from the LLM JSONL, tagged source='llm'
        ko = conn.execute(
            "SELECT g.text, g.source FROM gloss g JOIN kanji k ON g.kanji_id = k.id "
            "WHERE k.literal = '山' AND g.lang = 'ko'").fetchone()
        assert ko == ("메 산", "llm")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: FAIL — `build()` got an unexpected keyword argument `llm_glosses_path`.

- [ ] **Step 3: Wire the optional stage**

In `data-pipeline/kanjipipe/build_db.py`:

(a) add imports:
```python
from kanjipipe.ingest.llm_glosses import parse_llm_glosses
```
and extend the loader import to include `load_llm_glosses`:
```python
from kanjipipe.loader import (
    load_kanji, load_llm_glosses, load_relations, load_sentences,
    load_stroke_order, load_words)
```

(b) change the `build` signature to add an optional trailing keyword and load it
right after `load_kanji`:
```python
def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    jmdict_path: str | Path,
    sentences_path: str | Path,
    links_path: str | Path,
    out_path: str,
    llm_glosses_path: str | Path | None = None,
) -> dict[str, int]:
```
Inside the `try:` block, immediately after `load_kanji(conn, kanji)`:
```python
        if llm_glosses_path is not None and os.path.exists(llm_glosses_path):
            load_llm_glosses(conn, parse_llm_glosses(llm_glosses_path))
```

(c) in `main()`, add the argument and pass it (the real build auto-includes the
file when present, skips when absent):
```python
    parser.add_argument("--llm-glosses", default="sources/llm_glosses.jsonl")
```
and update the call:
```python
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.jmdict,
                   args.sentences, args.links, args.out,
                   llm_glosses_path=args.llm_glosses)
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_build_db.py -q`
Expected: PASS.

- [ ] **Step 5: Run the FULL suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add data-pipeline/kanjipipe/build_db.py data-pipeline/tests/test_build_db.py
git commit -m "feat(data-pipeline): build_db loads optional LLM native glosses"
```

---

## Task 5 (controller, not a TDD task): Generation run

After Tasks 1–4 are merged, the controller (Claude) generates
`sources/llm_glosses.jsonl`:
1. Pull the 2,136 jōyō kanji (literal + on/kun readings + English meaning) from
   the built `out/kanji.sqlite`.
2. Dispatch subagents over batches (~50 kanji) → each returns a JSON array of
   `{literal, ko (훈음), ja, zh}`; validate each batch (every literal present,
   no missing fields) before appending to the JSONL.
3. Generate **one sample batch first**, surface it for review; on approval,
   generate the rest.
4. Rebuild: `python -m kanjipipe.build_db --out out/kanji.sqlite` and verify
   `kanji_without_native_gloss == 0`.

This step is token-heavy and is run/observed directly, not via this plan's
checkbox tasks.

## Self-Review notes (addressed)

- **Spec coverage:** `LlmGloss` + parser (spec §5) → Task 1; `gloss.source` +
  `load_llm_glosses` (§4/§5) → Task 2; `kanji_without_native_gloss` non-gating
  report (§5) → Task 3; optional `llm_glosses_path` orchestration (§5) → Task 4;
  generation method (§3) → Task 5 (controller step).
- **Backward-compatible build():** the new `llm_glosses_path` is an optional
  trailing keyword with `None` default, so existing positional callers are
  unaffected; absent/missing file → stage skipped (fixture builds still work).
- **English glosses untouched:** `load_kanji` still inserts EN with `source` NULL;
  the loader test asserts `("mountain", None)` to lock that in.
- **Non-gating confirmed:** `kanji_without_native_gloss` is report-only;
  `assert_core_gates` unchanged (a hard gate is a documented follow-on once
  generation is verified complete).
- **Type consistency:** `LlmGloss{literal, ko, ja, zh}`,
  `parse_llm_glosses(path) -> list[LlmGloss]`, `load_llm_glosses(conn, entries)`,
  and the `kanji_without_native_gloss` key are used identically across tasks.

## Follow-on (not in this plan)

Promote native-gloss coverage to a hard gate; study-card UI; re-bundle the
enriched DB into the app.

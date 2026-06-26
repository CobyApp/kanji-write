# Promote Native-Gloss to a Hard Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (this is a single tiny task).

**Goal:** `assert_core_gates` fails the build when any kanji lacks a Korean (ko) native gloss.

**Tech Stack:** Python, pytest. `cd data-pipeline && .venv/bin/pytest -q`. `git` from repo root.

---

## Task 1: Add the gate + update tests (TDD)

**Files:**
- Modify: `data-pipeline/kanjipipe/validate.py`
- Modify: `data-pipeline/tests/test_validate.py`

- [ ] **Step 1: Write/adjust the failing tests**

In `data-pipeline/tests/test_validate.py`:

(a) Update the two "passes" tests to also seed a ko gloss so they still pass once
the gate exists. In `test_assert_core_gates_passes_on_complete_data` and
`test_assert_core_gates_passes_with_stroke_order`, after the
`load_stroke_order(conn, {0x5C71: ["d1"]})` line, add:
```python
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
```
(both tests use `_good()` which is 山 / codepoint 0x5C71; `load_llm_glosses` and
`LlmGloss` are already imported in this file.)

(b) Add a new failing-gate test:
```python
def test_assert_core_gates_fails_when_native_gloss_missing():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                 # 山, EN gloss + reading + grade
    load_stroke_order(conn, {0x5C71: ["d1"]})    # has strokes, but no ko gloss
    with pytest.raises(ValueError, match="missing native"):
        assert_core_gates(conn)
```

- [ ] **Step 2: Run to verify the new test fails**

Run: `cd data-pipeline && .venv/bin/pytest tests/test_validate.py -q`
Expected: `test_assert_core_gates_fails_when_native_gloss_missing` FAILS (no raise yet);
the two "passes" tests may now also fail until the gate is added (they seed ko but
the gate doesn't exist) — that's fine, the implementation step makes them green.

- [ ] **Step 3: Add the gate**

In `data-pipeline/kanjipipe/validate.py`, inside `assert_core_gates`, after the
`missing_stroke_order` check, add:
```python
    if report["kanji_without_native_gloss"]:
        problems.append(
            f"{report['kanji_without_native_gloss']} kanji missing native (ko) gloss")
```

- [ ] **Step 4: Run the full suite**

Run: `cd data-pipeline && .venv/bin/pytest -q`
Expected: all tests pass — the new fails-test raises, the two passes-tests are
seeded, the existing `fails_when_*` tests still match their substrings (the gate
concatenates all problems), and `test_build_db` passes (its fixture supplies ko
glosses for 山/学).

- [ ] **Step 5: Commit**

```bash
git add data-pipeline/kanjipipe/validate.py data-pipeline/tests/test_validate.py
git commit -m "feat(data-pipeline): gate the build on Korean native-gloss coverage"
```

## Self-Review
- The gate mirrors the stroke-order gate exactly; only `ko` is required (the
  signature gloss, fully populated). Existing `fails_when_*` tests use
  `pytest.raises(match=...)` which searches the concatenated message, so they
  remain green. The real build has `kanji_without_native_gloss == 0`.

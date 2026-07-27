# Kanken Advanced Levels Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add all 3,806 Unicode `準1級`/`1級` source rows, dual-level membership, and validated image-variant infrastructure while preserving every existing JLPT and Kanken feature.

**Architecture:** The Python pipeline becomes the only source of the bundled SQLite schema and Kanken allocation data. Kanken filtering moves from a single string column to a normalized membership table while retaining `kanji.kanken_level` as an introduction-level compatibility field. The Swift app loads memberships with each kanji, renders only verified glyph assets, and gates writing on verified stroke paths.

**Tech Stack:** Python 3.11, lxml, sqlite3, pytest 8; Swift 6, SwiftUI, GRDB, Composable Architecture, Tuist, XCTest.

## Global Constraints

- Pin `mimneko/kanji-data` commit `0be3577f7939ec85d2b4e373a7a94262e7449e13` and require CSV SHA-256 `e3a3bade7bb738f6e25d2ff14ea4118ed3b18d9cd32f49dd6a90f5eb6d8ef84f`.
- Treat the pinned CSV as authoritative: 4,177 advanced rows, 3,806 Unicode rows, and 371 image-only rows.
- Do not copy, vectorize, or bundle Kanjipedia images.
- Do not expose an image-only row without a reviewed GlyphWiki revision and SHA-256 manifest entry.
- A static glyph never implies stroke-order support.
- Keep all visible app copy Japanese; keep code, comments, tests, and documentation English.
- Preserve exact existing 10級–2級 incremental counts: 80, 160, 200, 202, 193, 191, 313, 284, 328, 185.
- Preserve `yojijukugo` and `taigirui` when rebuilding the database.
- Do not modify unrelated worksheet layout or counter behavior.
- Do not create Git commits unless the user explicitly requests them.

---

### Task 1: Parse and Pin Kanken Allocation Data

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/kanken.py`
- Create: `data-pipeline/tests/test_kanken.py`
- Create: `data-pipeline/tests/fixtures/kanken_sample.csv`
- Modify: `data-pipeline/kanjipipe/models.py`
- Modify: `data-pipeline/scripts/fetch_sources.sh`

**Interfaces:**
- Produces: `KankenAllocation(ct_id: str, ce_id: str, literal: str | None, variant_kind: str, source_level: str)`
- Produces: `parse_kanken_allocations(path: str | Path) -> list[KankenAllocation]`
- Produces: `memberships_for(source_level: str) -> tuple[str, ...]`
- Produces: pinned `data-pipeline/sources/kanken.csv`

- [ ] **Step 1: Write parser tests**

```python
def test_parse_kanken_allocations_handles_unicode_and_image_rows():
    rows = parse_kanken_allocations(FIX / "kanken_sample.csv")
    assert rows[0] == KankenAllocation(
        ct_id="CT-000002", ce_id="CE-000003", literal="亞",
        variant_kind="旧字", source_level="1/準1級",
    )
    assert rows[1].literal is None


def test_shared_level_expands_to_two_memberships():
    assert memberships_for("1/準1級") == ("準1級", "1級")


def test_unknown_level_fails():
    with pytest.raises(ValueError, match="unknown Kanken level"):
        memberships_for("特級")
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_kanken.py -q
```

Expected: collection fails because `kanjipipe.ingest.kanken` does not exist.

- [ ] **Step 3: Add the allocation model and parser**

```python
@dataclass(frozen=True)
class KankenAllocation:
    ct_id: str
    ce_id: str
    literal: str | None
    variant_kind: str
    source_level: str
```

```python
VALID_LEVELS = {
    "10級", "9級", "8級", "7級", "6級", "5級",
    "4級", "3級", "準2級", "2級", "準1級", "1/準1級", "1級",
}


def memberships_for(source_level: str) -> tuple[str, ...]:
    if source_level not in VALID_LEVELS:
        raise ValueError(f"unknown Kanken level: {source_level}")
    return ("準1級", "1級") if source_level == "1/準1級" else (source_level,)
```

The CSV parser must strip a BOM and header whitespace, preserve `CT-*` and
`CE-*`, and convert an empty `漢字テキスト` field to `None`.

- [ ] **Step 4: Pin the upstream fetch**

Add a fetch step that downloads the CSV from the exact commit, verifies a
checked-in SHA-256 constant, and writes `sources/kanken.csv` only after
verification. Keep the temporary file outside the destination path so a failed
download cannot replace a valid source.

- [ ] **Step 5: Run parser tests and the full Python suite**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_kanken.py -q
.venv/bin/pytest -q
```

Expected: both commands pass.

---

### Task 2: Make the Pipeline Schema Kanken-Complete

**Files:**
- Modify: `data-pipeline/kanjipipe/schema.py`
- Modify: `data-pipeline/kanjipipe/models.py`
- Modify: `data-pipeline/kanjipipe/loader.py`
- Modify: `data-pipeline/tests/test_db.py`
- Modify: `data-pipeline/tests/test_loader.py`

**Interfaces:**
- Produces: `load_kanken_memberships(conn, allocations) -> None`
- Produces: `kanken_membership(kanji_id, level_label, source_classification)`
- Produces: `glyph_asset`, `kanji_variant`, `yojijukugo`, and `taigirui` tables
- Retains: `kanji.kanken_level` as introduction level

- [ ] **Step 1: Write failing schema tests**

```python
def test_schema_contains_reproducible_kanken_tables():
    conn = init_db(":memory:")
    tables = {
        row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
    }
    assert {"kanken_membership", "glyph_asset", "kanji_variant",
            "yojijukugo", "taigirui"} <= tables
    columns = {row[1] for row in conn.execute("PRAGMA table_info(kanji)")}
    assert "kanken_level" in columns
```

```python
def test_shared_allocation_loads_two_memberships_with_pre1_intro_level():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced_kanji("亞")])
    load_kanken_memberships(conn, [_shared_allocation("亞")])
    levels = conn.execute(
        "SELECT level_label FROM kanken_membership ORDER BY level_label"
    ).fetchall()
    assert levels == [("1級",), ("準1級",)]
    assert conn.execute(
        "SELECT kanken_level FROM kanji WHERE literal = '亞'"
    ).fetchone() == ("準1級",)
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_db.py tests/test_loader.py -q
```

Expected: failures for missing column, tables, and loader.

- [ ] **Step 3: Add normalized schema**

Add foreign keys, uniqueness, and indexes:

```sql
CREATE TABLE kanken_membership (
    kanji_id              INTEGER NOT NULL REFERENCES kanji(id),
    level_label           TEXT NOT NULL,
    source_classification TEXT NOT NULL,
    UNIQUE(kanji_id, level_label)
);
CREATE INDEX idx_kanken_membership_level
    ON kanken_membership(level_label, kanji_id);
```

`glyph_asset` must require provider, glyph name, revision, SHA-256, source URL,
license URL, and local SVG resource name. `kanji_variant` must link a study
item to its canonical kanji and optional glyph asset.

- [ ] **Step 4: Add membership loading**

Resolve allocations by literal, expand `1/準1級`, insert memberships, and set
`kanji.kanken_level` to `準1級` for shared rows. Reject a Unicode allocation
whose literal is absent from the selected inventory.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_db.py tests/test_loader.py -q
.venv/bin/pytest -q
```

Expected: all pass.

---

### Task 3: Select Advanced Inventory and Build It Reproducibly

**Files:**
- Modify: `data-pipeline/kanjipipe/filters.py`
- Modify: `data-pipeline/kanjipipe/build_db.py`
- Modify: `data-pipeline/kanjipipe/validate.py`
- Modify: `data-pipeline/tests/test_build_db.py`
- Modify: `data-pipeline/tests/test_validate.py`
- Modify: `data-pipeline/tests/fixtures/kanjidic2_sample.xml`
- Modify: `data-pipeline/tests/fixtures/kanjivg_sample.xml`
- Create: `data-pipeline/tests/fixtures/kanken_build_sample.csv`

**Interfaces:**
- Produces: `select_study_inventory(kanji, allocations) -> list[Kanji]`
- Extends: `build(..., kanken_path, ...) -> dict[str, int]`
- Produces report keys: `kanken_unicode_advanced`, `kanken_image_pending`,
  `missing_kanken_membership`, `missing_advanced_reading`,
  `missing_advanced_meaning`

- [ ] **Step 1: Write failing inventory and build tests**

```python
def test_inventory_keeps_joyo_and_unicode_advanced_only():
    selected = select_study_inventory(
        [_joyo("山"), _advanced("亞"), _advanced("齷")],
        [_allocation("亞", "準1級"), _image_allocation("CE-image", "1級")],
    )
    assert [item.literal for item in selected] == ["山", "亞"]
```

Extend the build fixture test to assert:

```python
assert conn.execute(
    "SELECT COUNT(*) FROM kanken_membership WHERE level_label = '準1級'"
).fetchone()[0] == 1
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_build_db.py tests/test_validate.py -q
```

Expected: failures for the missing inventory selector, build argument, and
coverage keys.

- [ ] **Step 3: Replace the jōyō-only filter in `build()`**

Parse KANJIDIC2 first, parse Kanken allocations, then retain the union of jōyō
literals and Unicode advanced literals. Image-only rows remain in the pending
report and are not loaded as study items in Phase 1.

- [ ] **Step 4: Make validation capability-aware**

Keep existing gates for all Unicode rows except `grade`: advanced Kanken rows
may legitimately have no school grade. Require Japanese reading and at least
one meaning for every exposed advanced row. Require stroke data only for rows
marked writing-capable; missing KanjiVG data produces
`has_verified_stroke_order = false` instead of a fabricated path.

- [ ] **Step 5: Preserve curated Kanken tables**

Add build inputs and loaders for
`app/Sources/DictionaryClient/Resources/yojijukugo.source.json` and
`taigirui.source.json`, then assert fixture rows survive a clean build.

- [ ] **Step 6: Run all Python tests**

Run:

```bash
cd data-pipeline
.venv/bin/pytest -q
```

Expected: all pass.

---

### Task 4: Generate and Validate Glyph Candidate Manifests

**Files:**
- Create: `data-pipeline/kanjipipe/ingest/glyphwiki.py`
- Create: `data-pipeline/scripts/build_glyph_candidates.py`
- Create: `data-pipeline/sources/kanken_glyph_map.csv`
- Create: `data-pipeline/tests/test_glyphwiki.py`
- Modify: `data-pipeline/kanjipipe/validate.py`

**Interfaces:**
- Produces: `GlyphCandidate(ce_id, canonical_literal, glyph_name, match_basis)`
- Produces: `generate_candidates(allocations, glyph_dump, wikidata_rows) -> list[GlyphCandidate]`
- Produces: `parse_verified_glyph_manifest(path) -> list[GlyphAsset]`
- Produces: a candidate report accounting for all 371 image-only rows

- [ ] **Step 1: Write failing manifest tests**

```python
def test_unverified_manifest_row_is_rejected():
    with pytest.raises(ValueError, match="unverified glyph mapping"):
        parse_verified_glyph_manifest(FIX / "glyph_unverified.csv")


def test_verified_manifest_requires_revision_and_sha256():
    with pytest.raises(ValueError, match="revision and sha256"):
        parse_verified_glyph_manifest(FIX / "glyph_missing_hash.csv")


def test_candidate_report_accounts_for_every_image_row():
    report = generate_candidates(allocations, glyph_dump, wikidata_rows)
    assert {row.ce_id for row in report} == {
        row.ce_id for row in allocations if row.literal is None
    }
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_glyphwiki.py -q
```

Expected: import failure for the new module.

- [ ] **Step 3: Implement candidate generation without auto-selection**

Use `CT-ID` text siblings as canonical-parent candidates, GlyphWiki dump names
and aliases as glyph candidates, and Wikidata `P11318 → P5467` only as
additional evidence. Never convert a candidate into a verified mapping.

- [ ] **Step 4: Add strict verified-manifest parsing**

Accepted `match_basis` values are `unicode_exact`, `ivs_exact`,
`collection_id_exact`, and `manual_visual_verified`. Only
`verification_status=verified` rows with a pinned revision, source URL,
license URL, and SHA-256 can produce a `GlyphAsset`.

The Phase 1 checked-in manifest contains headers and any independently
verifiable mappings found during implementation; all remaining CE IDs stay in
the generated pending report.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
cd data-pipeline
.venv/bin/pytest tests/test_glyphwiki.py -q
.venv/bin/pytest -q
```

Expected: all pass and the report total equals 371.

---

### Task 5: Load Membership and Writing Capability in Swift

**Files:**
- Modify: `app/Sources/SharedModels/Kanji.swift`
- Modify: `app/Sources/DictionaryClient/DictionaryClient+Live.swift`
- Modify: `app/Sources/KanjiListFeature/KanjiListFeature.swift`
- Modify: `app/Sources/Review/Curriculum.swift`
- Modify: `app/Tests/KanjiListFeatureTests/KanjiFilterTests.swift`
- Modify: `app/Tests/ReviewTests/CurriculumTests.swift`
- Modify: `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`

**Interfaces:**
- Adds: `Kanji.kankenMemberships: [String]`
- Adds: `Kanji.hasVerifiedStrokeOrder: Bool`
- Adds: `Kanji.belongs(to level: String, exam: ExamType) -> Bool`
- Retains: `Kanji.kankenLevel` as introduction level

- [ ] **Step 1: Write failing pure-model tests**

```swift
func testSharedKankenItemBelongsToBothAdvancedLevels() {
    let item = Kanji.fixture(
        literal: "亞",
        kankenLevel: "準1級",
        kankenMemberships: ["準1級", "1級"]
    )
    XCTAssertTrue(item.belongs(to: "準1級", exam: .kanken))
    XCTAssertTrue(item.belongs(to: "1級", exam: .kanken))
}

func testKankenLevelsIncludeAdvancedLevels() {
    XCTAssertEqual(
        ExamType.kanken.levels.suffix(2),
        ["準1級", "1級"]
    )
}
```

- [ ] **Step 2: Run the focused Swift tests and confirm RED**

Run:

```bash
cd app
tuist generate --no-open
xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:KanjiListFeatureTests \
  -only-testing:ReviewTests
```

Expected: compile failures for missing properties and method.

- [ ] **Step 3: Extend `Kanji` and pure filters**

Use memberships for Kanken level inclusion and retain `jlptLevel` equality for
JLPT. Update `kanjiIn` and scoped `studyOrder` to call `belongs`.

- [ ] **Step 4: Load memberships in `allKanji`**

Replace N+1 membership reads with one grouped query or a join/group pass. Set
`hasVerifiedStrokeOrder` from an `EXISTS` subquery over `stroke_order`; do not
infer it from `stroke_count`.

- [ ] **Step 5: Replace Kanken SQL equality filters**

For `quizWords`, exam questions, radicals, strokes, okurigana, and on/kun
queries, use:

```sql
EXISTS (
    SELECT 1
    FROM kanken_membership km
    WHERE km.kanji_id = k.id
      AND km.level_label = ?
)
```

Keep JLPT filtering on `jlpt_level`.

- [ ] **Step 6: Add live database assertions**

Assert non-zero `準1級` and `1級` membership counts, one shared ID appearing in
both scopes, exact legacy-level counts, and a total kanji count greater than
2,136. Do not hard-code a final total until the pinned build report is known.

- [ ] **Step 7: Run focused tests**

Run the command from Step 2 plus:

```bash
xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:DictionaryClientTests
```

Expected: all focused tests pass.

---

### Task 6: Add Advanced Exam Sections and Safe Writing States

**Files:**
- Modify: `app/Sources/SharedModels/KankenQuestion.swift`
- Modify: `app/Sources/SharedModels/UIStrings.swift`
- Modify: `app/Sources/WritingCanvas/KanjiWritingFeature.swift`
- Modify: `app/Sources/WritingCanvas/KanjiWritingView.swift`
- Modify: `app/Sources/Worksheet/WorksheetView.swift`
- Modify: `app/Sources/Practice/PracticeFeature.swift`
- Modify: `app/Tests/TestModeTests/TestModeTests.swift`
- Modify: `app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift`
- Modify: `app/Tests/WorksheetTests/WorksheetTests.swift`
- Modify: `app/Tests/PracticeTests/PracticeGridTests.swift`

**Interfaces:**
- Adds Japanese copy: `筆順データがありません`
- Adds: `KanjiWritingFeature.State.isWritingAvailable`
- Adds explicit `準1級` and `1級` paper-section catalogs

- [ ] **Step 1: Write failing section and capability tests**

```swift
func testAdvancedKankenSectionsAreExplicitAndUnverifiedSectionsStayUnavailable() {
    let pre1 = ExamType.kanken.sections(for: "準1級")
    let level1 = ExamType.kanken.sections(for: "1級")
    XCTAssertFalse(pre1.isEmpty)
    XCTAssertFalse(level1.isEmpty)
    XCTAssertTrue(pre1.contains { !$0.available })
    XCTAssertTrue(level1.contains { !$0.available })
}
```

```swift
func testWritingUnavailableWithoutVerifiedStrokePaths() async {
    var state = KanjiWritingFeature.State(kanji: .withoutStrokeData)
    XCTAssertFalse(state.isWritingAvailable)
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
cd app
tuist generate --no-open
xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TestModeTests \
  -only-testing:WritingCanvasTests \
  -only-testing:WorksheetTests \
  -only-testing:PracticeTests
```

Expected: compile or assertion failures for the missing behavior.

- [ ] **Step 3: Add official advanced section structures**

Represent the real paper order. Mark only sections supported by reliable
current data as playable; show all others as `準備中`. Do not generate
questions from unrelated JLPT rows when an advanced section has no valid bank.

- [ ] **Step 4: Gate writing by verified paths**

When `hasVerifiedStrokeOrder` is false, keep the kanji readable and studyable
but replace tracing/animation entry points with `筆順データがありません`.
Do not alter worksheet deck positioning, counters, or navigation.

- [ ] **Step 5: Run focused tests**

Run the command from Step 2.

Expected: all focused tests pass.

---

### Task 7: Build, Bundle, and Verify the Complete Phase 1 Dataset

**Files:**
- Modify: `app/Sources/DictionaryClient/Resources/kanji.sqlite`
- Modify: `docs/kanken-exam-hub.md`

**Interfaces:**
- Consumes every interface from Tasks 1–6
- Produces the reproducible bundled SQLite database

- [ ] **Step 1: Run the full Python suite**

```bash
cd data-pipeline
.venv/bin/pytest -q
```

Expected: all tests pass.

- [ ] **Step 2: Fetch pinned sources and build to a temporary output**

```bash
cd data-pipeline
bash scripts/fetch_sources.sh
.venv/bin/python -m kanjipipe.build_db \
  --kanken sources/kanken.csv \
  --out out/kanji.sqlite
```

Expected build report:

- exact legacy Kanken counts unchanged
- `kanken_unicode_advanced = 3806`
- `kanken_image_pending = 371`
- no exposed Unicode advanced item missing required reading or meaning
- no unverified glyph asset loaded

- [ ] **Step 3: Inspect database invariants**

Run SQL assertions for foreign-key integrity, duplicate memberships, advanced
level counts, shared dual memberships, curated table counts, and orphaned
stroke paths. Any non-zero integrity error blocks bundling.

- [ ] **Step 4: Replace the bundled database**

Copy only after Steps 1–3 pass:

```bash
cp data-pipeline/out/kanji.sqlite \
  app/Sources/DictionaryClient/Resources/kanji.sqlite
```

- [ ] **Step 5: Run the complete app test suite**

```bash
cd app
tuist install
tuist generate --no-open
xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all test targets pass.

- [ ] **Step 6: Update documentation with measured results**

Record the pinned commit/hash, exact built counts, Unicode coverage, pending
image-only count, writing-capable count, and the rule that unverified variants
remain hidden.

- [ ] **Step 7: Final workspace verification**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; changed files are limited to this feature and
the previously approved design/plan documents.

---

## Phase 2 Handoff

Phase 2 uses the same schema and app code. For each of the 371 pending rows, a
reviewer must select an exact open glyph, pin its revision and hash in
`kanken_glyph_map.csv`, and confirm its canonical parent. A later implementation
plan can batch only verified manifest rows; no application architecture change
is required.

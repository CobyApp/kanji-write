# tests/test_validate.py
import pytest

from kanjipipe.db import init_db
from kanjipipe.loader import (
    load_kanji,
    load_kanken_memberships,
    load_llm_glosses,
    load_stroke_order,
    load_words,
)
from kanjipipe.models import Gloss, Kanji, KankenAllocation, LlmGloss, Reading, Word
from kanjipipe.validate import (
    PRODUCTION_KANKEN_COUNT_POLICY,
    KankenCountPolicy,
    assert_core_gates,
    coverage_report,
)


def _good():
    return Kanji(literal="山", codepoint=0x5C71, stroke_count=3, grade=1,
                 freq_rank=360, radical=46, jlpt_level="N5",
                 readings=[Reading("on", "サン")],
                 glosses=[Gloss("en", "mountain")])


def _advanced():
    return Kanji(
        literal="亞",
        codepoint=0x4E9E,
        stroke_count=8,
        grade=None,
        freq_rank=None,
        radical=7,
        readings=[Reading("on", "ア")],
        glosses=[Gloss("en", "Asia")],
    )


def _advanced_allocation():
    return KankenAllocation(
        ct_id="CT-000002",
        ce_id="CE-000003",
        literal="亞",
        variant_kind="旧字",
        source_level="1/準1級",
    )


def _image_allocation(ce_id: str = "CE-image"):
    return KankenAllocation(
        ct_id="CT-image",
        ce_id=ce_id,
        literal=None,
        variant_kind="旧字でない異体字",
        source_level="1級",
    )


def _overlapping_joyo():
    return Kanji(
        literal="予",
        codepoint=0x4E88,
        stroke_count=4,
        grade=3,
        freq_rank=180,
        radical=6,
        readings=[Reading("on", "ヨ")],
        glosses=[Gloss("en", "beforehand")],
    )


def _overlapping_allocations():
    return [
        KankenAllocation(
            ct_id="CT-overlap",
            ce_id=f"CE-overlap-{level}",
            literal="予",
            variant_kind="標準字体",
            source_level=level,
        )
        for level in ("8級", "1級")
    ]


def test_production_kanken_count_policy_is_canonical():
    assert PRODUCTION_KANKEN_COUNT_POLICY == KankenCountPolicy(
        legacy_memberships={
            "10級": 80,
            "9級": 160,
            "8級": 200,
            "7級": 202,
            "6級": 193,
            "5級": 191,
            "4級": 313,
            "3級": 284,
            "準2級": 328,
            "2級": 185,
        },
        unicode_advanced=3806,
        image_pending=371,
        advanced_memberships={"準1級": 1248, "1級": 2955},
        shared_advanced=397,
    )


def test_kanken_count_gate_measures_allocations_and_loaded_memberships():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced()])
    allocations = [_advanced_allocation(), _image_allocation()]
    load_kanken_memberships(conn, allocations)
    fixture_policy = KankenCountPolicy(
        legacy_memberships={},
        unicode_advanced=1,
        image_pending=1,
        advanced_memberships={"準1級": 1, "1級": 1},
        shared_advanced=1,
    )

    report = assert_core_gates(
        conn,
        kanken_allocations=allocations,
        kanken_count_policy=fixture_policy,
    )

    assert report["kanken_unicode_advanced"] == 1
    assert report["kanken_image_pending"] == 1
    assert report["kanken_pre1_memberships"] == 1
    assert report["kanken_level1_memberships"] == 1
    assert report["kanken_shared_advanced"] == 1


def test_kanken_count_gate_rejects_mismatched_parsed_shared_distribution():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced()])
    allocations = [_advanced_allocation(), _image_allocation()]
    load_kanken_memberships(conn, allocations)
    wrong_policy = KankenCountPolicy(
        legacy_memberships={},
        unicode_advanced=1,
        image_pending=1,
        advanced_memberships={"準1級": 1, "1級": 1},
        shared_advanced=0,
    )

    with pytest.raises(
        ValueError,
        match="parsed shared advanced memberships expected 0, got 1",
    ):
        assert_core_gates(
            conn,
            kanken_allocations=allocations,
            kanken_count_policy=wrong_policy,
        )


def test_kanken_count_gate_rejects_mismatched_loaded_advanced_distribution():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced()])
    allocations = [_advanced_allocation(), _image_allocation()]
    load_kanken_memberships(conn, allocations)
    conn.execute(
        "DELETE FROM kanken_membership WHERE level_label = '準1級'"
    )
    policy = KankenCountPolicy(
        legacy_memberships={},
        unicode_advanced=1,
        image_pending=1,
        advanced_memberships={"準1級": 1, "1級": 1},
        shared_advanced=1,
    )

    with pytest.raises(
        ValueError,
        match="loaded 準1級 memberships expected 1, got 0",
    ):
        assert_core_gates(
            conn,
            kanken_allocations=allocations,
            kanken_count_policy=policy,
        )


def test_kanken_count_gate_rejects_mismatched_parsed_allocation_counts():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced()])
    allocations = [_advanced_allocation(), _image_allocation()]
    load_kanken_memberships(conn, allocations)
    wrong_policy = KankenCountPolicy(
        legacy_memberships={},
        unicode_advanced=2,
        image_pending=1,
        advanced_memberships={"準1級": 1, "1級": 1},
        shared_advanced=1,
    )

    with pytest.raises(
        ValueError,
        match="kanken_unicode_advanced expected 2, got 1",
    ):
        assert_core_gates(
            conn,
            kanken_allocations=allocations,
            kanken_count_policy=wrong_policy,
        )


def test_kanken_count_gate_rejects_mismatched_loaded_legacy_counts():
    conn = init_db(":memory:")
    good = _good()
    allocation = KankenAllocation(
        ct_id="CT-legacy",
        ce_id="CE-legacy",
        literal="山",
        variant_kind="標準字体",
        source_level="10級",
    )
    load_kanji(conn, [good])
    load_kanken_memberships(conn, [allocation])
    load_stroke_order(conn, {good.codepoint: ["d1"]})
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
    wrong_policy = KankenCountPolicy(
        legacy_memberships={"10級": 2},
        unicode_advanced=0,
        image_pending=0,
        advanced_memberships={"準1級": 0, "1級": 0},
        shared_advanced=0,
    )

    with pytest.raises(
        ValueError,
        match="10級 memberships expected 2, got 1",
    ):
        assert_core_gates(
            conn,
            kanken_allocations=[allocation],
            kanken_count_policy=wrong_policy,
        )


def test_coverage_report_counts_gaps():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    report = coverage_report(conn)
    assert report["total"] == 1
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0
    assert report["missing_grade"] == 0
    assert report["missing_stroke_order"] == 1  # _good() has no strokes seeded
    assert report["kanken_unicode_advanced"] == 0
    assert report["kanken_image_pending"] == 0
    assert report["missing_kanken_membership"] == 0
    assert report["missing_advanced_reading"] == 0
    assert report["missing_advanced_meaning"] == 0


def test_advanced_row_allows_capability_gaps_but_requires_source_content():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced()])
    allocations = [
        _advanced_allocation(),
        _image_allocation("CE-image-1"),
        _image_allocation("CE-image-2"),
    ]
    load_kanken_memberships(conn, allocations)

    report = assert_core_gates(
        conn,
        kanken_allocations=allocations,
        kanken_count_policy=KankenCountPolicy(
            legacy_memberships={},
            unicode_advanced=1,
            image_pending=2,
            advanced_memberships={"準1級": 1, "1級": 1},
            shared_advanced=1,
        ),
    )

    assert report["missing_grade"] == 1
    assert report["missing_stroke_order"] == 1
    assert report["kanji_without_native_gloss"] == 1
    assert report["kanken_unicode_advanced"] == 1
    assert report["kanken_image_pending"] == 2


def test_advanced_row_requires_japanese_reading():
    conn = init_db(":memory:")
    advanced = _advanced()
    advanced.readings = [Reading("pinyin", "ya4")]
    load_kanji(conn, [advanced])
    load_kanken_memberships(conn, [_advanced_allocation()])

    with pytest.raises(ValueError, match="advanced kanji missing Japanese reading"):
        assert_core_gates(conn)


def test_advanced_row_requires_english_meaning():
    conn = init_db(":memory:")
    advanced = _advanced()
    advanced.glosses = []
    load_kanji(conn, [advanced])
    load_kanken_memberships(conn, [_advanced_allocation()])

    with pytest.raises(ValueError, match="advanced kanji missing meaning"):
        assert_core_gates(conn)


def test_overlapping_joyo_advanced_row_still_requires_stroke_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_overlapping_joyo()])
    load_kanken_memberships(conn, _overlapping_allocations())
    load_llm_glosses(conn, [LlmGloss(literal="予", ko="미리 예")])

    with pytest.raises(ValueError, match="missing stroke order"):
        assert_core_gates(conn)


def test_overlapping_joyo_advanced_row_still_requires_native_gloss():
    conn = init_db(":memory:")
    load_kanji(conn, [_overlapping_joyo()])
    load_kanken_memberships(conn, _overlapping_allocations())
    load_stroke_order(conn, {0x4E88: ["exact-path"]})

    with pytest.raises(ValueError, match="missing native"):
        assert_core_gates(conn)


def test_overlapping_legacy_advanced_row_still_requires_grade():
    conn = init_db(":memory:")
    overlap = _overlapping_joyo()
    overlap.grade = None
    load_kanji(conn, [overlap])
    load_kanken_memberships(conn, _overlapping_allocations())
    load_stroke_order(conn, {0x4E88: ["exact-path"]})
    load_llm_glosses(conn, [LlmGloss(literal="予", ko="미리 예")])

    with pytest.raises(ValueError, match="missing grade"):
        assert_core_gates(conn)


def test_gate_rejects_stroke_capability_mismatch():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced()])
    load_kanken_memberships(conn, [_advanced_allocation()])
    conn.execute(
        "UPDATE kanji SET has_verified_stroke_order = 1 WHERE literal = '亞'"
    )

    with pytest.raises(ValueError, match="stroke capability mismatch"):
        assert_core_gates(conn)


def test_assert_core_gates_passes_on_complete_data():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
    assert assert_core_gates(conn)["total"] == 1


def test_assert_core_gates_fails_when_english_missing():
    conn = init_db(":memory:")
    no_gloss = _good()
    no_gloss.glosses = []
    load_kanji(conn, [no_gloss])
    with pytest.raises(ValueError, match="missing EN meaning"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_when_reading_missing():
    conn = init_db(":memory:")
    no_reading = _good()
    no_reading.readings = []
    load_kanji(conn, [no_reading])
    with pytest.raises(ValueError, match="missing readings"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_when_grade_missing():
    conn = init_db(":memory:")
    no_grade = _good()
    no_grade.grade = None
    load_kanji(conn, [no_grade])
    with pytest.raises(ValueError, match="missing grade"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_on_empty_db():
    conn = init_db(":memory:")
    with pytest.raises(ValueError, match="no kanji loaded"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_when_stroke_order_missing():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])          # has reading + EN gloss + grade, but no strokes
    with pytest.raises(ValueError, match="missing stroke order"):
        assert_core_gates(conn)


def test_assert_core_gates_passes_with_stroke_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])          # _good() is 山, codepoint 0x5C71
    load_stroke_order(conn, {0x5C71: ["d1"]})
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
    assert assert_core_gates(conn)["missing_stroke_order"] == 0


def test_assert_core_gates_fails_when_native_gloss_missing():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                  # EN gloss + reading + grade
    load_stroke_order(conn, {0x5C71: ["d1"]})     # has strokes, but no ko gloss
    with pytest.raises(ValueError, match="missing native"):
        assert_core_gates(conn)


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
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
    # gate passes even though 山 has no words (vocabulary is supplementary)
    assert assert_core_gates(conn)["kanji_without_words"] == 1


def test_coverage_report_counts_kanji_without_sentences():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                 # 山
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert coverage_report(conn)["kanji_without_sentences"] == 1


def test_gates_do_not_fail_on_missing_sentences():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    load_llm_glosses(conn, [LlmGloss(literal="山", ko="메 산")])
    assert assert_core_gates(conn)["kanji_without_sentences"] == 1


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

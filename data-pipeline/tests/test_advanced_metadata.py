import json
import zipfile
from pathlib import Path

import pytest

from kanjipipe.db import init_db
from kanjipipe.filters import advanced_coverage, select_study_inventory
from kanjipipe.ingest.kanken_supplement import (
    DEFAULT_SUPPLEMENT_PATH,
    Provenance,
    SupplementEntry,
    parse_kanken_supplement,
)
from kanjipipe.ingest.unihan import (
    UNIHAN_LICENSE_URL,
    UNIHAN_SHA256,
    UNIHAN_URL,
    UnihanMetadata,
    parse_unihan,
)
from kanjipipe.loader import load_kanji, load_stroke_order
from kanjipipe.models import Gloss, Kanji, KankenAllocation, Reading


def _kanji(
    literal: str,
    *,
    grade: int | None = None,
    meaning: str | None = "exact",
    reading: str | None = "ア",
    stroke_count: int = 8,
) -> Kanji:
    return Kanji(
        literal=literal,
        codepoint=ord(literal),
        stroke_count=stroke_count,
        grade=grade,
        freq_rank=None,
        radical=1,
        readings=[Reading("on", reading)] if reading else [],
        glosses=[Gloss("en", meaning)] if meaning else [],
    )


def _allocation(
    literal: str,
    *,
    ct_id: str,
    source_level: str = "1級",
) -> KankenAllocation:
    return KankenAllocation(
        ct_id=ct_id,
        ce_id=f"CE-{ord(literal):X}",
        literal=literal,
        variant_kind="標準字体",
        source_level=source_level,
    )


def _provenance(literal: str) -> tuple[Provenance, ...]:
    return (
        Provenance(
            source="test",
            source_id=f"U+{ord(literal):04X}",
            url=f"https://example.test/{ord(literal):04X}",
            license="test-only",
            relationship="direct_character",
        ),
    )


def _supplement(
    literal: str,
    *,
    meaning: str | None = None,
    readings: tuple[tuple[str, str], ...] = (),
) -> SupplementEntry:
    return SupplementEntry(
        literal=literal,
        readings=readings,
        english_glosses=(meaning,) if meaning else (),
        provenance=_provenance(literal),
    )


def _unihan(literal: str, definition: str | None) -> UnihanMetadata:
    return UnihanMetadata(
        literal=literal,
        stroke_count=17,
        radical=75,
        on_readings=(),
        kun_readings=(),
        definition=definition,
    )


def _english(item: Kanji) -> list[str]:
    return [gloss.text for gloss in item.glosses if gloss.lang == "en"]


def test_metadata_precedence_is_exact_then_nfkc_then_ct_sibling():
    exact = _kanji("亞", meaning="exact KANJIDIC2")
    normalized = _kanji("晴", meaning="NFKC KANJIDIC2", stroke_count=12)
    sibling = _kanji("悦", meaning="CT sibling KANJIDIC2", stroke_count=10)
    allocations = [
        _allocation("亞", ct_id="CT-exact"),
        _allocation("晴", ct_id="CT-nfkc"),
        _allocation("悅", ct_id="CT-sibling"),
        _allocation("悦", ct_id="CT-sibling", source_level="配当外"),
    ]
    unihan = {
        literal: _unihan(literal, "Unihan")
        for literal in ("亞", "晴", "悅")
    }
    supplements = {
        literal: _supplement(literal, meaning="supplement")
        for literal in ("亞", "晴", "悅")
    }

    selected = select_study_inventory(
        [exact, normalized, sibling],
        allocations,
        unihan=unihan,
        supplements=supplements,
    )
    by_literal = {item.literal: item for item in selected}

    assert _english(by_literal["亞"]) == ["exact KANJIDIC2"]
    assert _english(by_literal["晴"]) == ["NFKC KANJIDIC2"]
    assert _english(by_literal["悅"]) == ["CT sibling KANJIDIC2"]


def test_unihan_then_curated_supplement_fill_only_missing_metadata():
    exact_without_meaning = _kanji("鮇", meaning=None, reading="ミ")
    allocations = [
        _allocation("檔", ct_id="CT-unihan"),
        _allocation("鮇", ct_id="CT-supplement"),
    ]
    unihan = {
        "檔": _unihan("檔", "shelf; frame, crosspiece"),
        "鮇": _unihan("鮇", None),
    }
    supplements = {
        "檔": _supplement("檔", readings=(("on", "トウ"), ("kun", "かまち"))),
        "鮇": _supplement("鮇", meaning="freshwater char"),
    }

    selected = select_study_inventory(
        [exact_without_meaning],
        allocations,
        unihan=unihan,
        supplements=supplements,
    )
    by_literal = {item.literal: item for item in selected}

    assert _english(by_literal["檔"]) == ["shelf; frame, crosspiece"]
    assert {(r.lang_axis, r.value) for r in by_literal["檔"].readings} == {
        ("on", "トウ"),
        ("kun", "かまち"),
    }
    assert _english(by_literal["鮇"]) == ["freshwater char"]
    assert advanced_coverage(selected, allocations) == {
        "missing_advanced_inventory": 0,
        "missing_advanced_reading": 0,
        "missing_advanced_meaning": 0,
    }


def test_nfkc_metadata_never_inherits_parent_stroke_paths():
    parent = _kanji("晴", meaning="clear weather", reading="セイ", stroke_count=12)
    allocations = [_allocation("晴", ct_id="CT-weather")]
    selected = select_study_inventory([parent], allocations)
    variant = next(item for item in selected if item.literal == "晴")
    assert variant.codepoint == ord("晴")
    assert variant.stroke_count == 12

    conn = init_db(":memory:")
    load_kanji(conn, selected)
    load_stroke_order(conn, {ord("晴"): ["parent-path"]})
    count = conn.execute(
        "SELECT COUNT(*) FROM stroke_order so "
        "JOIN kanji k ON k.id = so.kanji_id WHERE k.literal = '晴'"
    ).fetchone()[0]
    assert count == 0
    assert conn.execute(
        "SELECT has_verified_stroke_order FROM kanji WHERE literal = '晴'"
    ).fetchone() == (0,)


def test_parse_unihan_verifies_pin_and_exact_properties(tmp_path):
    archive = tmp_path / "Unihan.zip"
    with zipfile.ZipFile(archive, "w") as output:
        output.writestr(
            "Unihan_Readings.txt",
            "U+6A94\tkDefinition\tshelf; frame, crosspiece\n"
            "U+6A94\tkJapaneseOn\tTOU\n",
        )
        output.writestr(
            "Unihan_IRGSources.txt",
            "U+6A94\tkTotalStrokes\t17\n"
            "U+6A94\tkRSUnicode\t75.13\n"
            "U+4E9E\tkTotalStrokes\t8\n"
            "U+4E9E\tkRSUnicode\t120'.3\n",
        )
        output.writestr("Unihan_RadicalStrokeCounts.txt", "")

    parsed = parse_unihan(archive, expected_sha256=None)

    assert parsed["檔"] == UnihanMetadata(
        literal="檔",
        stroke_count=17,
        radical=75,
        on_readings=("TOU",),
        kun_readings=(),
        definition="shelf; frame, crosspiece",
    )
    assert parsed["亞"].radical == 120
    with pytest.raises(ValueError, match="Unihan SHA-256 mismatch"):
        parse_unihan(archive)
    assert UNIHAN_URL == "https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip"
    assert UNIHAN_SHA256 == (
        "f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e"
    )
    assert UNIHAN_LICENSE_URL == "https://www.unicode.org/license.txt"


def test_curated_supplement_requires_auditable_provenance(tmp_path):
    path = tmp_path / "supplement.json"
    path.write_text(
        json.dumps(
            {
                "version": 1,
                "entries": [
                    {
                        "literal": "檔",
                        "readings": [{"axis": "on", "value": "トウ"}],
                        "englishGlosses": [],
                        "provenance": [],
                    }
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="provenance"):
        parse_kanken_supplement(path)


@pytest.mark.parametrize(
    ("relationship", "message"),
    [
        ("unreviewed", "relationship"),
        ("direct_character", "readings or English glosses"),
    ],
)
def test_curated_supplement_validates_relationship_and_content(
    tmp_path,
    relationship,
    message,
):
    path = tmp_path / "supplement.json"
    path.write_text(
        json.dumps(
            {
                "version": 1,
                "entries": [
                    {
                        "literal": "檔",
                        "readings": [],
                        "englishGlosses": [],
                        "provenance": [
                            {
                                "source": "test",
                                "sourceId": "U+6A94",
                                "url": "https://example.test/6A94",
                                "license": "test-only",
                                "relationship": relationship,
                            }
                        ],
                    }
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match=message):
        parse_kanken_supplement(path)


def test_missing_unihan_archive_has_actionable_fetch_error(tmp_path):
    missing = tmp_path / "Unihan.zip"

    with pytest.raises(
        FileNotFoundError,
        match=r"scripts/fetch_sources\.sh",
    ):
        parse_unihan(missing)


def test_checked_in_supplement_covers_exact_residuals():
    entries = parse_kanken_supplement(DEFAULT_SUPPLEMENT_PATH)

    assert entries["檔"].readings == (("on", "トウ"), ("kun", "かまち"))
    meaning_literals = {
        literal for literal, entry in entries.items() if entry.english_glosses
    }
    assert meaning_literals == set(
        "慠檋癴籡粏苆蝲踑躮鎺驎魸鮇鮱鮲鯐鰘鰙鰚鱩鵇鵥鶎"
    )
    assert all(entry.provenance for entry in entries.values())
    assert all(
        source.source_id
        and source.url
        and source.license
        and source.relationship
        for entry in entries.values()
        for source in entry.provenance
    )
    indirect_jmdict = {
        literal
        for literal, entry in entries.items()
        for source in entry.provenance
        if source.source == "EDRDG JMdict"
        and source.relationship == "indirect_lexical_anchor"
    }
    assert indirect_jmdict == set("檋踑躮魸鮇鮱鯐鰘鰚鵥鶎")
    assert all(
        source.relationship == "verification_only"
        for entry in entries.values()
        for source in entry.provenance
        if source.source == "Kanjipedia"
    )


def test_unihan_parses_the_primary_korean_reading(tmp_path):
    """kanjidic2's first korean_h is not the primary reading.

    It gave 阿 as 옥 and 丑 as 추 — wrong for 570 of the 6,352 kanji that have
    one. Unihan's kHangul lists the primary first, so that is the better source.
    """
    archive = tmp_path / "Unihan.zip"
    with zipfile.ZipFile(archive, "w") as handle:
        handle.writestr(
            "Unihan_Readings.txt",
            "U+963F\tkHangul\t\uc544:0N\n"
            "U+4E11\tkHangul\t\ucd95:0E \ucd94:0N\n")
        handle.writestr("Unihan_IRGSources.txt", "")
        handle.writestr("Unihan_RadicalStrokeCounts.txt", "")

    parsed = parse_unihan(archive, expected_sha256=None)
    assert parsed["\u963f"].korean_reading == "\uc544"
    # Several listed — the first is the primary.
    assert parsed["\u4e11"].korean_reading == "\ucd95"

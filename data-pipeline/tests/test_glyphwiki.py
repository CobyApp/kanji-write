from __future__ import annotations

import csv
from pathlib import Path

import pytest

from kanjipipe.ingest.glyphwiki import (
    GlyphCandidate,
    GlyphExportEntry,
    WikidataExportEvidence,
    generate_candidates,
    parse_curated_glyphwiki_export_csv,
    parse_curated_wikidata_export_csv,
)
from kanjipipe.ingest.kanken import parse_kanken_allocations
from kanjipipe.models import KankenAllocation
from kanjipipe.validate import parse_verified_glyph_manifest
from scripts.build_glyph_candidates import (
    build_argument_parser,
    main,
    write_candidate_report,
)


def _allocation(
    ce_id: str,
    literal: str | None,
    *,
    ct_id: str = "CT-000001",
    source_level: str = "1級",
) -> KankenAllocation:
    return KankenAllocation(
        ct_id=ct_id,
        ce_id=ce_id,
        literal=literal,
        variant_kind="異体字",
        source_level=source_level,
    )


def _write_manifest(path: Path, **overrides: str) -> None:
    row = {
        "ce_id": "CE-000002",
        "canonical_literal": "亜",
        "glyph_name": "u4e9c-var-001",
        "match_basis": "manual_visual_verified",
        "verification_status": "verified",
        "provider": "glyphwiki",
        "revision": "42",
        "sha256": "a" * 64,
        "source_url": "https://glyphwiki.org/glyph/u4e9c-var-001",
        "license_url": "https://glyphwiki.org/license.html",
        "local_svg_name": "CE-000002.svg",
    }
    row.update(overrides)
    with path.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=row)
        writer.writeheader()
        writer.writerow(row)


def test_unverified_manifest_row_is_rejected(tmp_path: Path):
    manifest = tmp_path / "glyph_unverified.csv"
    _write_manifest(manifest, verification_status="candidate")

    with pytest.raises(ValueError, match="unverified glyph mapping"):
        parse_verified_glyph_manifest(manifest)


def test_verified_manifest_requires_revision_and_sha256(tmp_path: Path):
    manifest = tmp_path / "glyph_missing_hash.csv"
    _write_manifest(manifest, revision="", sha256="")

    with pytest.raises(ValueError, match="revision and sha256"):
        parse_verified_glyph_manifest(manifest)


@pytest.mark.parametrize("revision", ["latest", "r42", "0"])
def test_verified_manifest_requires_numeric_pinned_revision(
    tmp_path: Path,
    revision: str,
):
    manifest = tmp_path / "glyph_unpinned_revision.csv"
    _write_manifest(manifest, revision=revision)

    with pytest.raises(ValueError, match="numeric revision"):
        parse_verified_glyph_manifest(manifest)


@pytest.mark.parametrize(
    "field",
    ["source_url", "license_url"],
)
def test_verified_manifest_requires_https_urls(tmp_path: Path, field: str):
    manifest = tmp_path / "glyph_insecure_url.csv"
    _write_manifest(manifest, **{field: "http://glyphwiki.org/insecure"})

    with pytest.raises(ValueError, match="HTTPS source and license URLs"):
        parse_verified_glyph_manifest(manifest)


def test_verified_manifest_requires_allowed_basis_urls_and_parent(tmp_path: Path):
    manifest = tmp_path / "glyph_invalid.csv"

    _write_manifest(manifest, match_basis="wikidata_hint")
    with pytest.raises(ValueError, match="match_basis"):
        parse_verified_glyph_manifest(manifest)

    _write_manifest(manifest, match_basis="unicode_exact", source_url="")
    with pytest.raises(ValueError, match="source and license URLs"):
        parse_verified_glyph_manifest(manifest)

    _write_manifest(manifest, canonical_literal="")
    with pytest.raises(ValueError, match="canonical parent"):
        parse_verified_glyph_manifest(manifest)


def test_verified_manifest_produces_pinned_glyph_asset(tmp_path: Path):
    manifest = tmp_path / "glyph_verified.csv"
    _write_manifest(manifest)

    assets = parse_verified_glyph_manifest(manifest)

    assert len(assets) == 1
    assert assets[0].ce_id == "CE-000002"
    assert assets[0].canonical_literal == "亜"
    assert assets[0].revision == "42"
    assert assets[0].sha256 == "a" * 64


def test_parse_curated_glyphwiki_export_preserves_names_and_aliases(
    tmp_path: Path,
):
    export = tmp_path / "glyphwiki_export.csv"
    export.write_text(
        "glyph_name,alias\n"
        "u4e9c-var-001,u4e9c-itaiji-001\n"
        "u4e9c,\n",
        encoding="utf-8",
    )

    assert parse_curated_glyphwiki_export_csv(export) == [
        GlyphExportEntry("u4e9c", ()),
        GlyphExportEntry("u4e9c-var-001", ("u4e9c-itaiji-001",)),
    ]


def test_parse_curated_wikidata_export(tmp_path: Path):
    export = tmp_path / "wikidata_export.csv"
    export.write_text(
        "ce_id,glyph_name\n"
        "CE-000002,u4e9c-itaiji-001\n",
        encoding="utf-8",
    )

    assert parse_curated_wikidata_export_csv(export) == [
        WikidataExportEvidence("CE-000002", "u4e9c-itaiji-001")
    ]


def test_candidate_report_accounts_for_every_image_row_without_auto_selection():
    allocations = [
        _allocation("CE-000001", "亜"),
        _allocation("CE-000002", None),
        _allocation("CE-000003", None, ct_id="CT-000002"),
        _allocation("CE-000004", "仮", ct_id="CT-000002"),
    ]
    glyph_export = [
        GlyphExportEntry("u4e9c-var-001", ("u4e9c-itaiji-001",)),
    ]
    wikidata_rows = [
        WikidataExportEvidence(
            ce_id="CE-000002",
            glyph_name="u4e9c-itaiji-001",
        )
    ]

    report = generate_candidates(allocations, glyph_export, wikidata_rows)

    assert {row.ce_id for row in report} == {"CE-000002", "CE-000003"}
    assert report == [
        GlyphCandidate(
            ce_id="CE-000002",
            canonical_literal="亜",
            glyph_name="u4e9c-itaiji-001",
            match_basis="glyphwiki_alias",
            source_glyph_name="u4e9c-var-001",
        ),
        GlyphCandidate(
            ce_id="CE-000002",
            canonical_literal="亜",
            glyph_name="u4e9c-itaiji-001",
            match_basis="wikidata_candidate",
            source_glyph_name=None,
        ),
        GlyphCandidate(
            ce_id="CE-000002",
            canonical_literal="亜",
            glyph_name="u4e9c-var-001",
            match_basis="glyphwiki_name",
            source_glyph_name="u4e9c-var-001",
        ),
        GlyphCandidate(
            ce_id="CE-000003",
            canonical_literal="仮",
            glyph_name=None,
            match_basis=None,
            source_glyph_name=None,
        ),
    ]


def test_non_advanced_image_rows_are_intentionally_excluded():
    """Phase 1 accounts only for 準1級/1級 image rows, not 配当外 rows."""
    allocations = [
        _allocation("CE-000001", "亜"),
        _allocation("CE-000002", None),
        _allocation("CE-000003", None, source_level="配当外"),
    ]

    report = generate_candidates(allocations, [], [])

    assert [row.ce_id for row in report] == ["CE-000002"]


def test_multi_codepoint_canonical_is_explicitly_left_unmatched():
    allocations = [
        _allocation("CE-000001", "葛󠄀"),
        _allocation("CE-000002", None),
    ]

    assert generate_candidates(allocations, [], []) == [
        GlyphCandidate("CE-000002", "葛󠄀", None, None, None)
    ]


def test_candidate_report_writer_keeps_unresolved_rows(tmp_path: Path):
    output = tmp_path / "candidates.csv"

    write_candidate_report(
        output,
        [GlyphCandidate("CE-000002", "亜", None, None, None)],
    )

    assert output.read_bytes() == (
        "ce_id,canonical_literal,glyph_name,match_basis,source_glyph_name\n"
        "CE-000002,亜,,,\n"
    ).encode()
    assert b"\r" not in output.read_bytes()


def test_cli_uses_curated_export_options(tmp_path: Path):
    allocations = tmp_path / "allocations.csv"
    allocations.write_text(
        "字種ID,字項ID,漢字テキスト,字体,漢検級\n"
        "CT-000001,CE-000001,亜,親字,準1級\n"
        "CT-000001,CE-000002,,異体字,1級\n",
        encoding="utf-8",
    )
    glyph_export = tmp_path / "glyphwiki_export.csv"
    glyph_export.write_text(
        "glyph_name,alias\nu4e9c-var-001,u4e9c-itaiji-001\n",
        encoding="utf-8",
    )
    wikidata_export = tmp_path / "wikidata_export.csv"
    wikidata_export.write_text(
        "ce_id,glyph_name\nCE-000002,u4e9c-itaiji-001\n",
        encoding="utf-8",
    )
    output = tmp_path / "report.csv"

    main(
        [
            "--allocations",
            str(allocations),
            "--glyphwiki-export-csv",
            str(glyph_export),
            "--wikidata-export-csv",
            str(wikidata_export),
            "--output",
            str(output),
        ]
    )

    report = output.read_text(encoding="utf-8")
    assert "glyphwiki_alias,u4e9c-var-001" in report
    assert "wikidata_candidate," in report
    help_text = build_argument_parser().format_help()
    assert "dump_newest_only.txt" in help_text
    assert "SPARQL JSON" in help_text


def test_candidates_cover_every_advanced_image_only_entry():
    pipeline = Path(__file__).parents[1]
    ADVANCED = {"準1級", "1/準1級", "1級"}
    allocations = parse_kanken_allocations(pipeline / "sources/kanken.csv")
    expected = {
        row.ce_id
        for row in allocations
        if row.literal is None and row.source_level in ADVANCED
    }
    excluded = {
        row.ce_id
        for row in allocations
        if row.literal is None and row.source_level not in ADVANCED
    }

    assert parse_verified_glyph_manifest(
        pipeline / "sources/kanken_glyph_map.csv"
    ) == []
    with (pipeline / "sources/kanken_glyph_candidates.csv").open(
        encoding="utf-8", newline=""
    ) as source:
        rows = list(csv.DictReader(source))

    actual = {row["ce_id"] for row in rows}
    # The candidate sheet still covers all 371 image-only advanced entries; 117 of
    # them have since been resolved to a character, which is the next assertion.
    assert len(expected) == 371
    assert actual == expected
    assert actual.isdisjoint(excluded)
    assert all(row["ce_id"] for row in rows)
    assert b"\r" not in (
        pipeline / "sources/kanken_glyph_candidates.csv"
    ).read_bytes()


def test_resolved_literals_close_117_of_the_image_only_entries():
    """The 親字 entries now arrive with their canonical character, so only the 旧字
    variant rows are still waiting on a verified glyph."""
    pipeline = Path(__file__).parents[1]
    ADVANCED = {"準1級", "1/準1級", "1級"}

    def pending(resolved: bool) -> set[str]:
        allocations = parse_kanken_allocations(
            pipeline / "sources/kanken.csv",
            resolved_literals_path=(
                pipeline / "sources/kanken_resolved_literals.csv" if resolved else None),
        )
        return {
            row.ce_id for row in allocations
            if row.literal is None and row.source_level in ADVANCED
        }

    before, after = pending(False), pending(True)
    assert len(before) == 371
    assert len(after) == 254
    assert len(before - after) == 117
    assert after < before


def test_a_standard_form_reference_is_not_rankable():
    """Kanjipedia names some images after the canonical character's own codepoint
    — 棚 (U+68DA) links pr_68DA.png — and that is a picture of the standard
    character, not of its 旧字. Ranking candidates by likeness to it would pick
    whichever is *closest to the standard form*, the opposite of the variant being
    looked for, so those entries must not be auto-confirmed."""
    import sys
    sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
    from match_glyph_candidates import reference_is_the_variant

    standard = {
        "canonical_literal": "棚",
        "image_url": "https://www.kanjipedia.jp/common/images/kanji/60/pr_68DA.png",
    }
    variant = {
        "canonical_literal": "異",
        "image_url": "https://www.kanjipedia.jp/common/images/kanji/60/skj_8001.png",
    }

    assert reference_is_the_variant(standard) is False
    assert reference_is_the_variant(variant) is True
    assert reference_is_the_variant({"canonical_literal": "棚", "image_url": ""}) is False

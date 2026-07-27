from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from kanjipipe.models import KankenAllocation


ADVANCED_KANKEN_LEVELS = {"準1級", "1/準1級", "1級"}


@dataclass(frozen=True, order=True)
class GlyphExportEntry:
    glyph_name: str
    aliases: tuple[str, ...] = ()


@dataclass(frozen=True, order=True)
class WikidataExportEvidence:
    ce_id: str
    glyph_name: str


@dataclass(frozen=True, order=True)
class GlyphCandidate:
    ce_id: str
    canonical_literal: str | None
    glyph_name: str | None
    match_basis: str | None
    source_glyph_name: str | None


def parse_curated_glyphwiki_export_csv(
    path: str | Path,
) -> list[GlyphExportEntry]:
    """Read a curated CSV with exactly ``glyph_name,alias`` columns.

    This adapter does not parse GlyphWiki ``dump_newest_only.txt``. Convert the
    raw dump to this reviewed intermediate CSV before calling it. Multiple
    aliases in the ``alias`` column are separated with ``|``.
    """
    with Path(path).open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        expected = ["glyph_name", "alias"]
        if reader.fieldnames != expected:
            raise ValueError(
                "curated GlyphWiki export requires exactly glyph_name,alias columns"
            )

        aliases_by_name: dict[str, set[str]] = {}
        for row in reader:
            glyph_name = row["glyph_name"].strip()
            if not glyph_name:
                raise ValueError(
                    "curated GlyphWiki export contains an empty glyph name"
                )
            aliases = aliases_by_name.setdefault(glyph_name, set())
            aliases.update(
                alias.strip()
                for alias in row["alias"].split("|")
                if alias.strip()
            )

    return [
        GlyphExportEntry(name, tuple(sorted(aliases)))
        for name, aliases in sorted(aliases_by_name.items())
    ]


def parse_curated_wikidata_export_csv(
    path: str | Path,
) -> list[WikidataExportEvidence]:
    """Read a curated CSV with exactly ``ce_id,glyph_name`` columns.

    This adapter does not parse Wikidata SPARQL JSON. Convert and review the
    raw query response before calling it; rows remain candidate evidence only.
    """
    with Path(path).open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        expected = ["ce_id", "glyph_name"]
        if reader.fieldnames != expected:
            raise ValueError(
                "curated Wikidata export requires exactly ce_id,glyph_name columns"
            )
        evidence = {
            WikidataExportEvidence(
                ce_id=row["ce_id"].strip(),
                glyph_name=row["glyph_name"].strip(),
            )
            for row in reader
            if row["ce_id"].strip() and row["glyph_name"].strip()
        }
    return sorted(evidence)


def _canonical_by_ct_id(
    allocations: Iterable[KankenAllocation],
) -> dict[str, str]:
    text_rows: dict[str, list[KankenAllocation]] = {}
    for row in allocations:
        if row.literal is not None:
            text_rows.setdefault(row.ct_id, []).append(row)

    result: dict[str, str] = {}
    for ct_id, rows in text_rows.items():
        rows.sort(key=lambda row: (row.variant_kind != "親字", row.ce_id, row.literal))
        literal = rows[0].literal
        if literal is not None:
            result[ct_id] = literal
    return result


def _glyph_prefix(literal: str) -> str | None:
    if len(literal) != 1:
        return None
    return f"u{ord(literal):x}"


def _index_glyph_export(
    entries: Iterable[GlyphExportEntry],
) -> dict[str, tuple[tuple[str, str, str], ...]]:
    index: dict[str, set[tuple[str, str, str]]] = {}
    for entry in set(entries):
        names = ((entry.glyph_name, "glyphwiki_name"),) + tuple(
            (alias, "glyphwiki_alias") for alias in entry.aliases
        )
        for glyph_name, match_basis in names:
            prefix = glyph_name.split("-", 1)[0]
            index.setdefault(prefix, set()).add(
                (glyph_name, match_basis, entry.glyph_name)
            )
    return {
        prefix: tuple(sorted(candidates))
        for prefix, candidates in index.items()
    }


def generate_candidates(
    allocations: Iterable[KankenAllocation],
    glyph_export: Iterable[GlyphExportEntry],
    wikidata_rows: Iterable[WikidataExportEvidence],
) -> list[GlyphCandidate]:
    allocation_rows = list(allocations)
    canonical_by_ct_id = _canonical_by_ct_id(allocation_rows)
    glyphs_by_prefix = _index_glyph_export(glyph_export)
    wikidata_by_ce_id: dict[str, set[str]] = {}
    for row in wikidata_rows:
        wikidata_by_ce_id.setdefault(row.ce_id, set()).add(row.glyph_name)

    result: list[GlyphCandidate] = []
    for allocation in sorted(
        (
            row
            for row in allocation_rows
            if row.literal is None
            and row.source_level in ADVANCED_KANKEN_LEVELS
        ),
        key=lambda row: row.ce_id,
    ):
        canonical = canonical_by_ct_id.get(allocation.ct_id)
        candidates: set[tuple[str, str, str | None]] = set()

        if canonical:
            prefix = _glyph_prefix(canonical)
            if prefix is not None:
                candidates.update(glyphs_by_prefix.get(prefix, ()))

        for glyph_name in wikidata_by_ce_id.get(allocation.ce_id, set()):
            candidates.add((glyph_name, "wikidata_candidate", None))

        if not candidates:
            result.append(
                GlyphCandidate(allocation.ce_id, canonical, None, None, None)
            )
            continue

        result.extend(
            GlyphCandidate(
                allocation.ce_id,
                canonical,
                glyph_name,
                match_basis,
                source_glyph_name,
            )
            for glyph_name, match_basis, source_glyph_name in sorted(
                candidates,
                key=lambda item: (
                    item[0],
                    item[1],
                    item[2] or "",
                ),
            )
        )

    return result

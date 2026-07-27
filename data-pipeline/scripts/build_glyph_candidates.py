from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parents[1]
if str(PIPELINE_ROOT) not in sys.path:
    sys.path.insert(0, str(PIPELINE_ROOT))

from kanjipipe.ingest.glyphwiki import (
    GlyphCandidate,
    generate_candidates,
    parse_curated_glyphwiki_export_csv,
    parse_curated_wikidata_export_csv,
)
from kanjipipe.ingest.kanken import parse_kanken_allocations


def write_candidate_report(
    path: str | Path,
    candidates: list[GlyphCandidate],
) -> None:
    with Path(path).open("w", encoding="utf-8", newline="") as target:
        writer = csv.writer(target, lineterminator="\n")
        writer.writerow(
            (
                "ce_id",
                "canonical_literal",
                "glyph_name",
                "match_basis",
                "source_glyph_name",
            )
        )
        for candidate in candidates:
            writer.writerow(
                (
                    candidate.ce_id,
                    candidate.canonical_literal or "",
                    candidate.glyph_name or "",
                    candidate.match_basis or "",
                    candidate.source_glyph_name or "",
                )
            )


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build an evidence-only Kanken glyph candidate report from curated "
            "CSV exports. Raw GlyphWiki dump_newest_only.txt and Wikidata "
            "SPARQL JSON require separate conversion and review."
        )
    )
    parser.add_argument(
        "--allocations",
        type=Path,
        default=PIPELINE_ROOT / "sources/kanken.csv",
    )
    parser.add_argument(
        "--glyphwiki-export-csv",
        type=Path,
        help=(
            "Curated CSV with exactly glyph_name,alias columns; convert raw "
            "dump_newest_only.txt separately"
        ),
    )
    parser.add_argument(
        "--wikidata-export-csv",
        type=Path,
        help=(
            "Curated CSV with exactly ce_id,glyph_name columns; convert "
            "Wikidata SPARQL JSON separately"
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=PIPELINE_ROOT / "sources/kanken_glyph_candidates.csv",
    )
    return parser


def main(argv: list[str] | None = None) -> None:
    args = build_argument_parser().parse_args(argv)

    allocations = parse_kanken_allocations(args.allocations)
    glyph_export = (
        parse_curated_glyphwiki_export_csv(args.glyphwiki_export_csv)
        if args.glyphwiki_export_csv
        else []
    )
    wikidata_rows = (
        parse_curated_wikidata_export_csv(args.wikidata_export_csv)
        if args.wikidata_export_csv
        else []
    )
    candidates = generate_candidates(allocations, glyph_export, wikidata_rows)
    write_candidate_report(args.output, candidates)

    pending_count = len({candidate.ce_id for candidate in candidates})
    print(f"Wrote {len(candidates)} rows accounting for {pending_count} pending CE IDs")


if __name__ == "__main__":
    main()

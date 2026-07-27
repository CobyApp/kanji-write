"""Fetch GlyphWiki candidates for image-only Kanken variants and stage a review.

The 漢検漢字辞典 lists some 準1級/1級 variants only as a Kanjipedia bitmap — they
have no Unicode codepoint, so the app can't render them without a vector glyph.
This harness automates every deterministic step of sourcing those glyphs:

  probe  — derive candidate GlyphWiki names from the canonical parent, keep the
           ones that actually exist, and record each one's pinned revision.
  fetch  — download each surviving candidate's SVG, hash it, store it locally.
  sheet  — emit a self-contained HTML sheet placing the Kanjipedia reference
           image beside every candidate rendering, for side-by-side review.

What it deliberately does NOT do is decide which candidate is correct: several
plausible names usually resolve (IVS, koseki, …) and only a visual comparison
settles it. Reviewers record their choice in the review CSV; ``promote`` then
turns confirmed rows into verified manifest entries that
``validate.parse_verified_glyph_manifest`` accepts.

Usage:
    python3 scripts/fetch_glyph_assets.py probe    [--limit N]
    python3 scripts/fetch_glyph_assets.py fetch    [--limit N]
    python3 scripts/fetch_glyph_assets.py sheet
    python3 scripts/fetch_glyph_assets.py promote
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, asdict
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parents[1]
if str(PIPELINE_ROOT) not in sys.path:
    sys.path.insert(0, str(PIPELINE_ROOT))

SOURCES = PIPELINE_ROOT / "sources"
KANKEN_CSV = SOURCES / "kanken.csv"
GLYPH_DIR = SOURCES / "glyphs"
PROBE_JSON = SOURCES / "kanken_glyph_probe.json"
REVIEW_CSV = SOURCES / "kanken_glyph_review.csv"
MANIFEST_CSV = SOURCES / "kanken_glyph_map.csv"
SHEET_HTML = PIPELINE_ROOT / "out" / "glyph_review.html"

ADVANCED_LEVELS = {"準1級", "1/準1級", "1級"}
GLYPHWIKI_API = "https://glyphwiki.org/api/glyph?name={name}"
GLYPHWIKI_SVG = "https://glyphwiki.org/glyph/{name}.svg"
GLYPHWIKI_PAGE = "https://glyphwiki.org/wiki/{name}"
GLYPHWIKI_LICENSE = "https://glyphwiki.org/wiki/GlyphWiki:License"
USER_AGENT = "kanji-write-pipeline/1.0 (+glyph sourcing for Kanken variants)"
REQUEST_PAUSE = 0.34  # be a polite client — GlyphWiki is a small volunteer host


@dataclass
class Candidate:
    """One GlyphWiki name that exists, with the revision it resolved at."""

    glyph_name: str
    match_basis: str
    revision: str
    sha256: str = ""
    local_svg_name: str = ""


@dataclass
class Entry:
    """An image-only Kanken variant plus every candidate glyph found for it."""

    ce_id: str
    canonical_literal: str
    level: str
    variant_kind: str
    image_url: str
    candidates: list[Candidate]


# --- sources -----------------------------------------------------------------


def read_image_only_variants() -> list[Entry]:
    """Advanced-level rows that carry an image but no Unicode text."""
    with KANKEN_CSV.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))

    # A variant's canonical parent is the lettered row sharing its 字種ID (CT id),
    # preferring the 親字 — the same rule glyphwiki._canonical_by_ct_id applies, so
    # this harness and the candidate report agree on parentage.
    lettered_by_ct: dict[str, list[tuple[bool, str, str]]] = {}
    for row in rows:
        text = (row.get("漢字テキスト") or "").strip()
        if not text:
            continue
        ct_id = (row.get("字種ID") or "").strip()
        lettered_by_ct.setdefault(ct_id, []).append(
            ((row.get("字体") or "").strip() != "親字",
             (row.get("字項ID") or "").strip(), text)
        )
    parent_by_ct = {
        ct_id: sorted(items)[0][2] for ct_id, items in lettered_by_ct.items()
    }

    entries: list[Entry] = []
    for row in rows:
        if (row.get("漢字テキスト") or "").strip():
            continue
        if (row.get("漢検級") or "").strip() not in ADVANCED_LEVELS:
            continue
        entries.append(
            Entry(
                ce_id=(row.get("字項ID") or "").strip(),
                canonical_literal=parent_by_ct.get((row.get("字種ID") or "").strip(), ""),
                level=(row.get("漢検級") or "").strip(),
                variant_kind=(row.get("字体") or "").strip(),
                image_url=(row.get("漢字画像") or "").strip(),
                candidates=[],
            )
        )
    return entries


def candidate_names(parent: str) -> list[tuple[str, str]]:
    """Deterministic GlyphWiki names to try for a parent, with their match basis.

    Old forms are published under a few stable conventions: Ideographic
    Variation Sequences (``-ue01xx``), the source-separated J/K/T shapes, and
    the Koseki/Toki collections keyed by the parent. Existence is probed rather
    than assumed — most of these will 404 for any given parent.
    """
    if not parent:
        return []
    cp = ord(parent[0])
    base = f"u{cp:04x}"
    names: list[tuple[str, str]] = []
    for selector in range(0x100, 0x104):  # VS17–VS20 carry the common old forms
        names.append((f"{base}-ue{selector:04x}", "ivs_exact"))
    for suffix in ("k", "t", "j", "jv"):  # source-separated shapes
        names.append((f"{base}-{suffix}", "collection_id_exact"))
    names.append((base, "unicode_exact"))
    return names


# --- network -----------------------------------------------------------------


def _get(url: str, *, binary: bool = False):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    except urllib.error.URLError:
        return None
    time.sleep(REQUEST_PAUSE)
    return payload if binary else payload.decode("utf-8")


def probe_glyph(name: str) -> str | None:
    """Return the pinned revision if the glyph exists, else None."""
    body = _get(GLYPHWIKI_API.format(name=name))
    if not body:
        return None
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return None
    version = data.get("version")
    # A real glyph reports a positive integer version; absent glyphs report none.
    if not isinstance(version, int) or version < 1:
        return None
    return str(version)


# --- commands ----------------------------------------------------------------


def cmd_probe(args: argparse.Namespace) -> int:
    entries = read_image_only_variants()
    if args.limit:
        entries = entries[: args.limit]
    print(f"probing {len(entries)} image-only variants…")
    for index, entry in enumerate(entries, start=1):
        for name, basis in candidate_names(entry.canonical_literal):
            revision = probe_glyph(name)
            if revision:
                entry.candidates.append(Candidate(name, basis, revision))
        print(f"  [{index}/{len(entries)}] {entry.ce_id} {entry.canonical_literal} "
              f"→ {len(entry.candidates)} candidate(s)")
    PROBE_JSON.parent.mkdir(parents=True, exist_ok=True)
    PROBE_JSON.write_text(
        json.dumps([asdict(e) for e in entries], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    resolved = sum(1 for e in entries if e.candidates)
    print(f"\n{resolved}/{len(entries)} have at least one candidate → {PROBE_JSON}")
    return 0


def _load_probe() -> list[Entry]:
    raw = json.loads(PROBE_JSON.read_text(encoding="utf-8"))
    return [
        Entry(
            ce_id=item["ce_id"],
            canonical_literal=item["canonical_literal"],
            level=item["level"],
            variant_kind=item["variant_kind"],
            image_url=item["image_url"],
            candidates=[Candidate(**c) for c in item["candidates"]],
        )
        for item in raw
    ]


def cmd_fetch(args: argparse.Namespace) -> int:
    entries = _load_probe()
    GLYPH_DIR.mkdir(parents=True, exist_ok=True)
    targets = [e for e in entries if e.candidates]
    if args.limit:
        targets = targets[: args.limit]
    total = sum(len(e.candidates) for e in targets)
    print(f"fetching {total} candidate SVGs…")
    done = 0
    for entry in targets:
        for candidate in entry.candidates:
            svg = _get(GLYPHWIKI_SVG.format(name=candidate.glyph_name), binary=True)
            done += 1
            if not svg:
                print(f"  [{done}/{total}] {candidate.glyph_name}: no SVG")
                continue
            candidate.sha256 = hashlib.sha256(svg).hexdigest()
            candidate.local_svg_name = f"{candidate.glyph_name}.svg"
            (GLYPH_DIR / candidate.local_svg_name).write_bytes(svg)
            print(f"  [{done}/{total}] {candidate.glyph_name} @r{candidate.revision}")
    PROBE_JSON.write_text(
        json.dumps([asdict(e) for e in entries], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\nSVGs → {GLYPH_DIR}")
    _write_review_csv(entries)
    print(f"review sheet stub → {REVIEW_CSV}")
    return 0


def _write_review_csv(entries: list[Entry]) -> None:
    """A decision sheet: one row per candidate, `confirm` left blank for review."""
    with REVIEW_CSV.open("w", encoding="utf-8", newline="") as target:
        writer = csv.writer(target, lineterminator="\n")
        writer.writerow(
            ("ce_id", "canonical_literal", "level", "variant_kind", "image_url",
             "glyph_name", "match_basis", "revision", "sha256", "local_svg_name",
             "confirm")
        )
        for entry in entries:
            for candidate in entry.candidates:
                if not candidate.sha256:
                    continue
                writer.writerow(
                    (entry.ce_id, entry.canonical_literal, entry.level,
                     entry.variant_kind, entry.image_url, candidate.glyph_name,
                     candidate.match_basis, candidate.revision, candidate.sha256,
                     candidate.local_svg_name, "")
                )


def cmd_sheet(args: argparse.Namespace) -> int:
    """Render the Kanjipedia reference beside each candidate for visual review."""
    entries = [e for e in _load_probe() if any(c.sha256 for c in e.candidates)]
    parts = [
        "<meta charset='utf-8'><title>Kanken glyph review</title>",
        "<style>body{font-family:system-ui;margin:24px;background:#fff}"
        "section{border:1px solid #ddd;border-radius:12px;padding:14px;margin:14px 0}"
        "h2{font-size:16px;margin:0 0 10px}.row{display:flex;gap:20px;align-items:center;flex-wrap:wrap}"
        ".cand{text-align:center;font-size:12px;color:#444}"
        ".cand img{width:96px;height:96px;border:1px solid #eee;border-radius:8px;background:#fff}"
        ".ref img{width:96px;height:96px;border:2px solid #c33;border-radius:8px}"
        ".ref{text-align:center;font-size:12px;color:#c33;font-weight:600}</style>",
        f"<h1>漢検 image-only variants — {len(entries)} entries</h1>",
        "<p>Red = Kanjipedia reference. Pick the matching candidate and put its "
        "<code>glyph_name</code> in the <code>confirm</code> column of "
        "<code>kanken_glyph_review.csv</code>.</p>",
    ]
    for entry in entries:
        parts.append(
            f"<section><h2>{html.escape(entry.ce_id)} — parent "
            f"{html.escape(entry.canonical_literal)} · {html.escape(entry.level)} · "
            f"{html.escape(entry.variant_kind)}</h2><div class='row'>"
        )
        parts.append(
            f"<div class='ref'><img src='{html.escape(entry.image_url)}'>"
            f"<div>Kanjipedia</div></div>"
        )
        for candidate in entry.candidates:
            if not candidate.sha256:
                continue
            src = (GLYPH_DIR / candidate.local_svg_name).as_uri()
            parts.append(
                f"<div class='cand'><img src='{src}'>"
                f"<div>{html.escape(candidate.glyph_name)}</div>"
                f"<div>r{html.escape(candidate.revision)}</div></div>"
            )
        parts.append("</div></section>")
    SHEET_HTML.parent.mkdir(parents=True, exist_ok=True)
    SHEET_HTML.write_text("\n".join(parts), encoding="utf-8")
    print(f"review sheet → {SHEET_HTML}")
    return 0


def cmd_promote(args: argparse.Namespace) -> int:
    """Turn reviewer-confirmed rows into the verified manifest."""
    if not REVIEW_CSV.exists():
        print(f"no review sheet at {REVIEW_CSV}; run fetch first", file=sys.stderr)
        return 1
    with REVIEW_CSV.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))

    confirmed = [r for r in rows if (r.get("confirm") or "").strip()]
    if not confirmed:
        print("no confirmed rows — fill the `confirm` column first")
        return 1

    seen: set[str] = set()
    out: list[dict[str, str]] = []
    for row in confirmed:
        choice = row["confirm"].strip()
        if choice != row["glyph_name"].strip():
            continue  # `confirm` names the winning candidate for that CE
        if row["ce_id"] in seen:
            print(f"duplicate confirmation for {row['ce_id']}", file=sys.stderr)
            return 1
        seen.add(row["ce_id"])
        out.append({
            "ce_id": row["ce_id"],
            "canonical_literal": row["canonical_literal"],
            "glyph_name": row["glyph_name"],
            # A human compared it to the reference image, so record that basis.
            "match_basis": "manual_visual_verified",
            "verification_status": "verified",
            "provider": "glyphwiki",
            "revision": row["revision"],
            "sha256": row["sha256"],
            "source_url": GLYPHWIKI_PAGE.format(name=row["glyph_name"]),
            "license_url": GLYPHWIKI_LICENSE,
            "local_svg_name": row["local_svg_name"],
        })

    fields = ["ce_id", "canonical_literal", "glyph_name", "match_basis",
              "verification_status", "provider", "revision", "sha256",
              "source_url", "license_url", "local_svg_name"]
    with MANIFEST_CSV.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(out)
    print(f"wrote {len(out)} verified mapping(s) → {MANIFEST_CSV}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    probe = sub.add_parser("probe", help="find candidate glyph names + revisions")
    probe.add_argument("--limit", type=int, default=0)
    probe.set_defaults(func=cmd_probe)
    fetch = sub.add_parser("fetch", help="download candidate SVGs and hash them")
    fetch.add_argument("--limit", type=int, default=0)
    fetch.set_defaults(func=cmd_fetch)
    sheet = sub.add_parser("sheet", help="render the visual review sheet")
    sheet.set_defaults(func=cmd_sheet)
    promote = sub.add_parser("promote", help="confirmed rows → verified manifest")
    promote.set_defaults(func=cmd_promote)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

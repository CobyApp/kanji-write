"""Rank glyph candidates by how closely they match the Kanjipedia reference.

`fetch_glyph_assets.py` leaves several plausible GlyphWiki candidates per
variant; the dictionary's own bitmap is the ground truth for which one is meant.
This scores every candidate objectively instead of by eye: both images are
reduced to a normalised binary mask of the inked area and compared with
Intersection-over-Union, so differences in canvas size, padding and stroke
weight don't dominate.

The score is evidence for a reviewer, not an oracle: it fills the `confirm`
column only where the winner is clearly ahead of the runner-up, and flags the
rest for a human look.

Usage:
    python3 scripts/match_glyph_candidates.py score      # download refs + rank
    python3 scripts/match_glyph_candidates.py apply      # confirm clear winners
    python3 scripts/match_glyph_candidates.py sheet      # ranked review sheet
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import io
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
import cairosvg

PIPELINE_ROOT = Path(__file__).resolve().parents[1]
SOURCES = PIPELINE_ROOT / "sources"
GLYPH_DIR = SOURCES / "glyphs"
REF_DIR = SOURCES / "glyph_refs"
PROBE_JSON = SOURCES / "kanken_glyph_probe.json"
REVIEW_CSV = SOURCES / "kanken_glyph_review.csv"
SCORES_JSON = SOURCES / "kanken_glyph_scores.json"
SHEET_HTML = PIPELINE_ROOT / "out" / "glyph_match_review.html"

CANVAS = 128           # comparison resolution
USER_AGENT = "kanji-write-pipeline/1.0 (+glyph sourcing for Kanken variants)"
# A win is only auto-confirmed when it is both good on its own and clearly
# ahead of the next candidate — otherwise the shapes are too close to call.
MIN_IOU = 0.62
MIN_MARGIN = 0.045


# --- image handling ----------------------------------------------------------


def _normalise(mask: np.ndarray) -> np.ndarray | None:
    """Crop to the inked bounding box and rescale onto a fixed square canvas.

    Kanjipedia bitmaps and GlyphWiki SVGs use different margins and aspect
    padding; comparing raw canvases would mostly measure that. Cropping to the
    ink and re-fitting compares the glyph shapes themselves.
    """
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    top, bottom, left, right = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    cropped = mask[top:bottom, left:right]
    height, width = cropped.shape
    side = max(height, width)
    # Pad to a square first so the aspect ratio survives the resize.
    square = np.zeros((side, side), dtype=np.uint8)
    y0 = (side - height) // 2
    x0 = (side - width) // 2
    square[y0:y0 + height, x0:x0 + width] = cropped
    image = Image.fromarray(square * 255).resize((CANVAS, CANVAS), Image.LANCZOS)
    return (np.asarray(image) > 110).astype(np.uint8)


def mask_from_png(data: bytes) -> np.ndarray | None:
    image = Image.open(io.BytesIO(data))
    if image.mode in ("RGBA", "LA"):  # transparent background → alpha is the ink
        alpha = np.asarray(image.split()[-1])
        mask = (alpha > 40).astype(np.uint8)
    else:
        grey = np.asarray(image.convert("L"))
        mask = (grey < 160).astype(np.uint8)  # dark pixels are ink
    return _normalise(mask)


def mask_from_svg(path: Path) -> np.ndarray | None:
    try:
        png = cairosvg.svg2png(
            url=str(path), output_width=256, output_height=256,
            background_color="white",
        )
    except Exception:
        return None
    grey = np.asarray(Image.open(io.BytesIO(png)).convert("L"))
    return _normalise((grey < 160).astype(np.uint8))


def iou(a: np.ndarray, b: np.ndarray) -> float:
    union = np.logical_or(a, b).sum()
    if union == 0:
        return 0.0
    return float(np.logical_and(a, b).sum() / union)


# --- reference images --------------------------------------------------------


def fetch_reference(url: str, dest: Path) -> bytes | None:
    if dest.exists():
        return dest.read_bytes()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
            dest.write_bytes(payload)
            time.sleep(0.25)
            return payload
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
        except Exception:
            pass
        time.sleep(0.6 * attempt)
    return None


# --- commands ----------------------------------------------------------------


def cmd_score(args: argparse.Namespace) -> int:
    entries = [e for e in json.loads(PROBE_JSON.read_text(encoding="utf-8"))
               if e["candidates"]]
    REF_DIR.mkdir(parents=True, exist_ok=True)
    results = []
    for index, entry in enumerate(entries, start=1):
        ref_path = REF_DIR / f"{entry['ce_id']}.png"
        raw = fetch_reference(entry["image_url"], ref_path) if entry["image_url"] else None
        ref_mask = mask_from_png(raw) if raw else None
        scored = []
        if ref_mask is not None:
            for candidate in entry["candidates"]:
                svg = GLYPH_DIR / candidate["local_svg_name"]
                if not svg.exists():
                    continue
                mask = mask_from_svg(svg)
                if mask is None:
                    continue
                scored.append({
                    **candidate,
                    "iou": round(iou(ref_mask, mask), 4),
                    "_shape": hashlib.md5(mask.tobytes()).hexdigest(),
                })
        scored.sort(key=lambda c: (-c["iou"], len(c["glyph_name"]), c["glyph_name"]))
        # Several GlyphWiki names often alias to one shape (u95bc, -ue0100 and
        # -ue0102 render identically). Collapse those so a reviewer compares
        # distinct glyphs, not duplicates, and keep the most canonical name.
        deduped: list[dict] = []
        seen_shapes: set[str] = set()
        for candidate in scored:
            shape = candidate.pop("_shape", None)
            if shape is not None and shape in seen_shapes:
                deduped[-1].setdefault("aliases", []).append(candidate["glyph_name"])
                continue
            if shape is not None:
                seen_shapes.add(shape)
            deduped.append(candidate)
        scored = deduped
        best = scored[0]["iou"] if scored else 0.0
        second = scored[1]["iou"] if len(scored) > 1 else 0.0
        results.append({
            "ce_id": entry["ce_id"],
            "canonical_literal": entry["canonical_literal"],
            "level": entry["level"],
            "variant_kind": entry["variant_kind"],
            "image_url": entry["image_url"],
            "has_reference": ref_mask is not None,
            "best_iou": best,
            "margin": round(best - second, 4),
            "auto": bool(ref_mask is not None and best >= MIN_IOU
                         and (best - second) >= MIN_MARGIN),
            "candidates": scored,
        })
        if index % 25 == 0 or index == len(entries):
            print(f"  scored {index}/{len(entries)}")
    SCORES_JSON.write_text(json.dumps(results, ensure_ascii=False, indent=2),
                           encoding="utf-8")
    auto = sum(1 for r in results if r["auto"])
    noref = sum(1 for r in results if not r["has_reference"])
    print(f"\n{auto}/{len(results)} clear winners · {noref} without a reference image")
    print(f"→ {SCORES_JSON}")
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    """Write the clear winners into the review sheet's `confirm` column."""
    results = {r["ce_id"]: r for r in json.loads(SCORES_JSON.read_text(encoding="utf-8"))}
    with REVIEW_CSV.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))
        fields = list(rows[0].keys())

    confirmed = 0
    for row in rows:
        result = results.get(row["ce_id"])
        if not result or not result["auto"]:
            row["confirm"] = ""
            continue
        winner = result["candidates"][0]["glyph_name"]
        row["confirm"] = winner if row["glyph_name"] == winner else ""
        confirmed += 1 if row["confirm"] else 0

    with REVIEW_CSV.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"confirmed {confirmed} entries in {REVIEW_CSV}")
    return 0


def cmd_sheet(args: argparse.Namespace) -> int:
    """Review sheet ordered worst-match first, so doubtful cases come first."""
    results = json.loads(SCORES_JSON.read_text(encoding="utf-8"))
    results.sort(key=lambda r: (r["auto"], r["best_iou"]))
    parts = [
        "<meta charset='utf-8'><title>Glyph match review</title>",
        "<style>body{font-family:system-ui;margin:24px}"
        "section{border:1px solid #ddd;border-radius:12px;padding:14px;margin:14px 0}"
        "section.auto{border-color:#3a7;background:#f6fffa}"
        "section.manual{border-color:#e88;background:#fffaf6}"
        "h2{font-size:15px;margin:0 0 10px}.row{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-end}"
        ".c{text-align:center;font-size:11px;color:#555}"
        ".c img{width:88px;height:88px;border:1px solid #eee;background:#fff;border-radius:6px}"
        ".c.win img{border:3px solid #3a7}"
        ".ref img{width:88px;height:88px;border:3px solid #c33;border-radius:6px}"
        ".ref{text-align:center;font-size:11px;color:#c33;font-weight:700}</style>",
        f"<h1>Glyph match review — {len(results)} entries</h1>",
        f"<p>green = auto-confirmed (IoU ≥ {MIN_IOU}, margin ≥ {MIN_MARGIN}); "
        "orange = needs a human call. Doubtful cases first.</p>",
    ]
    for result in results:
        cls = "auto" if result["auto"] else "manual"
        parts.append(
            f"<section class='{cls}'><h2>{html.escape(result['ce_id'])} · parent "
            f"{html.escape(result['canonical_literal'])} · {html.escape(result['variant_kind'])} "
            f"· best IoU {result['best_iou']:.3f} (margin {result['margin']:.3f})</h2><div class='row'>"
        )
        ref = REF_DIR / f"{result['ce_id']}.png"
        if ref.exists():
            parts.append(f"<div class='ref'><img src='{ref.as_uri()}'><div>reference</div></div>")
        for rank, candidate in enumerate(result["candidates"][:6]):
            svg = GLYPH_DIR / candidate["local_svg_name"]
            win = " win" if rank == 0 and result["auto"] else ""
            parts.append(
                f"<div class='c{win}'><img src='{svg.as_uri()}'>"
                f"<div>{html.escape(candidate['glyph_name'])}</div>"
                f"<div>{candidate['iou']:.3f}</div></div>"
            )
        parts.append("</div></section>")
    SHEET_HTML.parent.mkdir(parents=True, exist_ok=True)
    SHEET_HTML.write_text("\n".join(parts), encoding="utf-8")
    print(f"→ {SHEET_HTML}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name, func, helptext in (
        ("score", cmd_score, "download references and rank candidates"),
        ("apply", cmd_apply, "confirm clear winners in the review sheet"),
        ("sheet", cmd_sheet, "render the ranked review sheet"),
    ):
        p = sub.add_parser(name, help=helptext)
        p.set_defaults(func=func)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

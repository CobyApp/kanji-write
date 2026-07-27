# 漢検 image-only variant glyphs (準1級 / 1級)

## What these are

The 漢検漢字辞典 lists 371 advanced-level entries that have **no Unicode
codepoint** — the dictionary shows them only as a Kanjipedia bitmap. They are
mostly 旧字 (old forms) of a parent kanji that *does* have a codepoint:

| 字体 | count |
|---|---|
| 旧字 (old form) | 247 |
| 親字 (head entry) | 122 |
| 旧字でない異体字 | 2 |

Because they have no codepoint, the app cannot render them from a font. They
need a vector glyph, which is what `glyph_asset` / `kanji_variant` hold. Until a
glyph is sourced, the entry is simply absent from the DB — the app never shows a
broken or guessed character.

## Not to be confused with: kanji missing stroke order

Separately, **265 real Unicode kanji** at 準1級/1級 (133 + 132) have no
per-stroke data, because KanjiVG does not cover them (verified: 0 of the 265
appear among KanjiVG's 6,699 glyphs). `has_verified_stroke_order = 0` marks
these, and the app disables writing practice for them with a clear notice.

**GlyphWiki cannot fix that gap.** Its SVGs are a *single filled outline path*
(山, a 3-stroke kanji, comes back as one `<path>`), so they can render a glyph
but carry no stroke separation or ordering. Sourcing stroke order for those 265
would require a different per-stroke source.

## Sourcing workflow

`data-pipeline/scripts/fetch_glyph_assets.py` automates every deterministic step
and stops where judgement is required.

```bash
cd data-pipeline
.venv/bin/python3 scripts/fetch_glyph_assets.py probe   # find names + revisions
.venv/bin/python3 scripts/fetch_glyph_assets.py fetch   # download + hash SVGs
.venv/bin/python3 scripts/fetch_glyph_assets.py sheet   # build the review sheet
# → review, fill the `confirm` column in sources/kanken_glyph_review.csv
.venv/bin/python3 scripts/fetch_glyph_assets.py promote # → kanken_glyph_map.csv
```

**probe** derives candidate GlyphWiki names from the canonical parent — the IVS
forms (`u{cp}-ue0100…ue0103`), the source-separated shapes (`-j/-k/-t/-jv`) and
the bare `u{cp}` — and keeps only names that actually resolve, recording each
one's pinned revision. Parentage uses the same rule as
`glyphwiki._canonical_by_ct_id`, so this agrees with the candidate report.

**fetch** downloads each surviving candidate, hashes it (sha256) and stores it
under `sources/glyphs/`, then writes the decision sheet
`sources/kanken_glyph_review.csv` with the `confirm` column left blank.

**sheet** renders `out/glyph_review.html`: the Kanjipedia reference image
(outlined red) beside every candidate glyph, so a reviewer can pick the match at
a glance.

**promote** turns confirmed rows into `sources/kanken_glyph_map.csv` with
`verification_status=verified`, `match_basis=manual_visual_verified`, the pinned
revision, sha256, and GlyphWiki source + license URLs. Output is accepted by
`validate.parse_verified_glyph_manifest` (verified end-to-end).

## Candidate ranking

`scripts/match_glyph_candidates.py` makes the review pass faster:

```bash
.venv/bin/python3 scripts/match_glyph_candidates.py score  # fetch refs + rank
.venv/bin/python3 scripts/match_glyph_candidates.py sheet  # ranked review sheet
.venv/bin/python3 scripts/match_glyph_candidates.py apply  # clear winners only
```

It fetches each entry's Kanjipedia bitmap, rasterises every candidate, and scores
them by IoU over normalised binary masks. It also **collapses candidates that
render identically** — GlyphWiki aliases several names to one shape — which cuts
the comparisons from 2,579 to 1,138, and sorts doubtful entries first in
`out/glyph_match_review.html`.

**The score is advisory, not decisive.** Across the 338 entries with a real
choice, median best IoU is 0.358 and median margin 0.018; only 7 clear a 0.10
margin. A 旧字 differs from its parent by a stroke or two, while the dictionary's
bitmap differs from GlyphWiki's outlines in weight and style far more than that,
so stroke weight swamps the distinguishing detail. Ranking narrows the field;
the final call stays human.

## Why review is not skipped

Several candidates usually resolve for the same parent — for 扱 alone,
`u6271-ue0100`, `u6271-ue0101` and `koseki-133200` all return HTTP 200. Only a
visual comparison against the Kanjipedia reference settles which is the 旧字 the
dictionary means, so the manifest records `manual_visual_verified` and the
pipeline refuses any row that is not explicitly `verified`.

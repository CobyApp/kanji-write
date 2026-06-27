# Stroke Scoring (geometric heuristic) — Design + Plan

Date: 2026-06-27
Status: Approved (delegated) — combined design + plan (fast path)
Builds on: writing-canvas slice. Uses existing `SVGPath` + the kanji's
`strokePaths` (KanjiVG) already loaded into `KanjiWritingFeature`.

## 1. Purpose

After writing, give the learner feedback by comparing their strokes to the
KanjiVG reference — without ML. A "採点" button reports stroke-count match and a
shape score from per-stroke endpoint proximity.

## 2. Approach (no ML — pure geometry)

For the reference (KanjiVG) and the user's `PKDrawing`, reduce each stroke to its
**(start, end) endpoints**. Normalize each set independently to a unit square
(by its combined bounding box, so canvas size is irrelevant). Compare stroke `i`
of the reference to stroke `i` of the user: it "matches" if both its start and
end are within a distance `threshold` (in unit space). Score = matched strokes /
max(referenceCount, drawnCount); also report whether the stroke counts are equal.

This is a coarse heuristic (endpoints + order), deliberately simple and robust —
not handwriting recognition (that remains a deferred, separate effort).

## 3. Components (in `WritingCanvas`)

Pure, unit-tested (`StrokeScoring.swift`):
- `struct StrokeEndpoints: Equatable, Sendable { var start: CGPoint; var end: CGPoint }`
- `func normalize(_ strokes: [StrokeEndpoints]) -> [StrokeEndpoints]` — map all
  points by the combined bounding box to `[0,1]²` (no-op-safe if bbox is a point:
  returns zeros).
- `func endpoints(ofSVGPath d: String) -> StrokeEndpoints?` — via `SVGPath.parse`:
  start = first `move` point; end = the last command's terminal point; nil if no
  drawable command.
- `struct StrokeScore: Equatable { var countMatch: Bool; var matched: Int; var total: Int; var percent: Int }`
- `func scoreStrokes(reference: [StrokeEndpoints], drawn: [StrokeEndpoints], threshold: CGFloat = 0.18) -> StrokeScore`
  — `total = max(reference.count, drawn.count)`; for `i` in the overlap, matched
  if `dist(ref[i].start, drawn[i].start) <= threshold && dist(end,end) <= threshold`;
  `percent = total == 0 ? 0 : matched*100/total`; `countMatch = reference.count == drawn.count`.

Glue (build/manual-QA, not unit-tested):
- `KanjiWritingView` derives drawn endpoints from `PKDrawing`:
  for each `PKStroke`, `stroke.path.first?.location` / `.last?.location` →
  `StrokeEndpoints`; `normalize(...)`; send `.score(drawn)`.
- `KanjiWritingFeature`: `State.score: StrokeScore?`; `Action.score([StrokeEndpoints])`;
  on `.score`, build reference endpoints from `state.strokePaths.compactMap(endpoints(ofSVGPath:))`,
  `normalize` them, `scoreStrokes(reference:drawn:)` → `state.score`. A 採点
  toolbar button (enabled when there's a drawing) sends `.score(...)`; the view
  shows e.g. "画数 ✓ ・ 形 80%".

## 4. Testing

- `endpoints(ofSVGPath:)`: `"M10,10 L90,90"` → start (10,10), end (90,90);
  a cubic `"M0,0 C…  e"` → start (0,0), end e; empty/`""` → nil.
- `normalize`: a set spanning (10,10)-(90,90) maps to corners 0 and 1; a single
  point → zeros (no div-by-zero).
- `scoreStrokes`: identical sets → percent 100, countMatch true; off-by-one
  count → countMatch false, total = max; a far-off stroke → not matched;
  empty → percent 0.
- `KanjiWritingFeature` (`TestStore`): `.score([...])` with known drawn endpoints
  vs a stubbed `strokePaths` state → sets `state.score` to the expected value.
- Build green. The PKDrawing→endpoints extraction and on-screen result are
  manual/device QA.

## 5. Build order

1. `StrokeScoring.swift` (StrokeEndpoints, normalize, endpoints, StrokeScore,
   scoreStrokes) + unit tests (TDD).
2. `KanjiWritingFeature`: `State.score`, `Action.score`, reducer using the pure
   funcs + feature test.
3. `KanjiWritingView`: derive drawn endpoints from `PKDrawing`, 採点 button,
   result display (build-verified).

## 6. Non-Goals / Follow-on

True handwriting/shape recognition (DTW over full sampled curves, direction
checks, ML); per-stroke red/green overlay; scoring history. This endpoint
heuristic is intentionally coarse.

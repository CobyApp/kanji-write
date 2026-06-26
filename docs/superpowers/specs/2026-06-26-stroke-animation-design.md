# Stroke-Order Animation — Design

Date: 2026-06-26
Status: Approved (delegated) — ready for implementation planning
Builds on: study-card + writing-canvas slices (merged). Uses the `stroke_order`
data already in the DB (`DictionaryClient.strokeOrder`).

## 1. Purpose

Show the kanji being written stroke-by-stroke, in order, as an animation in the
study card — making the stroke order easy to learn at a glance. Self-contained:
no new data, no SwiftData/notifications.

## 2. Scope & Non-Goals

In scope:
- A `StrokeOrderPlayer` SwiftUI view (in `WritingCanvas`) that animates the
  KanjiVG strokes drawing in order, with a replay button.
- A pure `strokeFraction(progress:index:)` helper (unit-tested).
- `KanjiDetailFeature` loads the kanji's stroke paths (via existing
  `DictionaryClient.strokeOrder`); `KanjiDetailView` shows a 画順 section.

Non-goals (follow-on):
- Replacing the writing-screen guide; per-stroke speed controls; stroke numbers;
  stroke-by-stroke step buttons.

## 3. Components

- **`strokeFraction(progress:index:) -> Double`** (in `WritingCanvas`): returns
  `min(max(progress - Double(index), 0), 1)` — how much of stroke `index` is
  drawn at overall `progress` (progress ranges 0...strokeCount). Pure,
  unit-testable.
- **`StrokesShape: Shape`** (in `WritingCanvas`): `animatableData` is the overall
  `progress`; `path(in:)` scales each KanjiVG path (`SVGPath`) to the square's
  109-unit viewBox and appends, per stroke, its `trimmedPath(from: 0, to:
  strokeFraction(progress, index))` so strokes complete one after another.
- **`StrokeOrderPlayer`** (in `WritingCanvas`): holds `@State progress`; renders
  `StrokesShape` stroked; a "再生" button resets to 0 and animates progress to
  `strokeCount` (`withAnimation(.easeInOut(duration: count * 0.5))`); shows the
  full glyph initially.
- **`KanjiDetailFeature`**: `State.strokePaths: [String]`; `onAppear` adds a 5th
  concurrent `dictionaryClient.strokeOrder(id)`; `loaded` carries it.
- **`KanjiDetailView`**: a 画順 section (shown when `!strokePaths.isEmpty`) with
  `StrokeOrderPlayer(paths: store.strokePaths)`.

## 4. Testing

- **`strokeFraction`**: 0 before the stroke starts, fractional mid-stroke, 1 once
  passed (e.g. `(progress: 1.5, index: 0) == 1`, `== 0.5` for index 1, `== 0` for
  index 2).
- **`KanjiDetailFeature`** (`TestStore`): `onAppear` → `loaded` now also
  populates `strokePaths` from the mocked `strokeOrder`.
- Build verification green; the animation itself is manual QA.

## 5. Build order

1. `strokeFraction` + `StrokesShape` + `StrokeOrderPlayer` (WritingCanvas) +
   helper unit test (TDD for the helper).
2. `KanjiDetailFeature` loads stroke paths (extend State/Action/onAppear/loaded)
   + updated feature test.
3. `KanjiDetailView` 画順 section (build-verified).

## 6. Follow-on

Step buttons, speed control, stroke numbers, writing-screen integration.

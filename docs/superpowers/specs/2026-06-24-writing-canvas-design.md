# Writing Canvas (PencilKit) — Design

Date: 2026-06-24
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: app scaffold (merged) + stroke-order pipeline slice (merged)

## 1. Purpose

The app's core interaction: write a kanji with a pressure-sensitive Apple
Pencil over a faint stroke-order guide. This slice adds a single-kanji writing
screen reachable by tapping a kanji in the list, rendering the KanjiVG stroke
guide (from the `stroke_order` data) beneath a PencilKit canvas.

## 2. Scope & Non-Goals

In scope:
- A new `WritingCanvas` module: an SVG-path parser, a PencilKit canvas wrapper,
  the `KanjiWritingFeature` reducer, and its view.
- A `DictionaryClient.strokeOrder(forKanjiID:)` endpoint (interface + GRDB live).
- Regenerating the bundled placeholder `kanji.sqlite` so it includes
  `stroke_order` (the current placeholder predates that table).
- Navigation: tap a kanji in the list → push the writing screen.

Non-goals (later sub-projects):
- Stroke-order *checking* / handwriting recognition / scoring.
- Persisting drawings (SwiftData `UserStore`).
- Stroke-order *animation* playback.
- Study plans, progress/SRS, multiple-kanji sessions.

## 3. Components (each one responsibility)

- **`SVGPath`** — parses a KanjiVG path `d` string into drawable geometry.
  - `SVGPath.parse(_ d: String) -> [SVGCommand]` — tokenizes the `d` string into
    a typed command list. Supports the commands KanjiVG emits: `M/m` (move),
    `L/l` (line), `C/c` (cubic), `S/s` (smooth cubic), `Z/z` (close). Pure and
    precisely unit-testable.
  - `SVGPath.path(from commands: [SVGCommand]) -> Path` — folds commands into a
    SwiftUI `Path`, tracking current point and the last control point for
    smooth-curve reflection. Relative commands resolve against the current point.
  - Out of scope: arcs (`A/a`), quadratics (`Q/T`) — KanjiVG does not use them;
    if an unsupported command appears, it is skipped (and logged) rather than
    crashing.
- **`PencilCanvasView`** — a `UIViewRepresentable` wrapping `PKCanvasView`.
  Exposes a binding so the feature can read/clear the `PKDrawing`. Uses
  `drawingPolicy = .anyInput` so it works in the simulator (finger) and on
  device (Pencil, with pressure) alike. No tool picker; a fixed pen tool.
- **`KanjiWritingFeature`** (TCA) — `@Reducer`.
  - `State`: `kanji: Kanji`, `strokePaths: [String]` (ordered `d` strings),
    `drawing: PKDrawing`, `showGuide: Bool` (default true).
  - `Action`: `onAppear`, `strokesLoaded([String])`, `toggleGuide`, `clear`.
  - `onAppear` → `@Dependency(\.dictionaryClient).strokeOrder(forKanjiID:)` →
    `strokesLoaded`. `clear` resets `drawing`. `toggleGuide` flips `showGuide`.
- **`KanjiWritingView`** — `ZStack` of the guide layer (each `strokePaths`
  entry parsed via `SVGPath` and stroked faintly, shown when `showGuide`) and
  `PencilCanvasView`, sized to a square that maps the KanjiVG 109×109 viewBox.
  Toolbar: toggle guide, clear.

## 4. DictionaryClient change (additive)

Add an endpoint:
```
var strokeOrder: @Sendable (_ kanjiID: Int) async throws -> [String]
```
Live (GRDB): `SELECT path_d FROM stroke_order WHERE kanji_id = ? ORDER BY ordinal`.
Existing `allKanji` is unchanged.

## 5. Navigation

`KanjiListFeature` gains a `.kanjiTapped(Kanji)` action. `AppFeature` owns a
`StackState`/`NavigationStack` path; tapping pushes a `KanjiWritingFeature`
scoped to the tapped kanji. `KanjiListView` becomes the stack root; rows are
buttons that send `.kanjiTapped`.

## 6. Data flow

`KanjiListView` tap → `AppFeature` pushes `KanjiWritingFeature(kanji)` →
`KanjiWritingView.onAppear` → `DictionaryClient.strokeOrder(kanji.id)` →
`strokePaths` → guide layer renders parsed `SVGPath`s; the PencilKit canvas
captures ink independently.

## 7. Placeholder DB regeneration

Run the pipeline `build()` over the three fixtures (kanjidic2 + jlpt + kanjivg)
to regenerate `app/Sources/DictionaryClient/Resources/kanji.sqlite` so 山/学
carry their strokes. Still a labeled placeholder; replaced by the real DB later.

## 8. Testing

- **`SVGPathParserTests`**: assert `parse` produces the exact `[SVGCommand]` for
  representative inputs covering `M`, `L`, `C`, `c`, `S`, `s`, `Z`, and that an
  unsupported command is skipped; assert `path(from:)` yields a non-empty
  `Path.boundingRect` for a real KanjiVG stroke.
- **`KanjiWritingFeatureTests`** (`TestStore`): `onAppear` loads `strokePaths`
  from an overridden `dictionaryClient.strokeOrder`; `toggleGuide` flips
  `showGuide`; `clear` empties `drawing`.
- **`DictionaryClientTests`** (integration): `liveValue.strokeOrder(forKanjiID:)`
  against the regenerated bundled DB returns 山's 3 ordered paths.
- **PencilKit canvas**: ink behavior is manual QA (cannot unit-test ink); only
  the build verifies the `UIViewRepresentable` compiles and renders.
- Verify: `tuist generate` + `xcodebuild test` on an iOS 26 simulator, green.

## 9. Build order (this slice)

1. `SVGPath` parser + command builder (TDD, pure — no Xcode UI needed to test
   logic, but runs in the test target).
2. `DictionaryClient.strokeOrder` endpoint + GRDB live + regenerate placeholder
   DB + integration test.
3. `KanjiWritingFeature` reducer + `TestStore` tests.
4. `PencilCanvasView` + `KanjiWritingView` (build-verified).
5. Navigation wiring (`KanjiListFeature.kanjiTapped`, `AppFeature` stack,
   `KanjiListView` rows) + full build/test green.

New module `WritingCanvas` + a `WritingCanvasTests` target are added to
`app/Project.swift` (as `.staticFramework` / `.unitTests`, matching the existing
modules). Gets its own implementation plan next.

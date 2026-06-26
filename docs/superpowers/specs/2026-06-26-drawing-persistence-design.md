# Drawing Persistence — Design

Date: 2026-06-26
Status: Approved (delegated) — ready for implementation planning
Builds on: writing-canvas slice (merged).

## 1. Purpose

Persist the learner's handwriting per kanji: when they reopen a kanji's writing
screen, their last drawing is restored, and a 保存 button saves the current ink.

## 2. Scope & Non-Goals

In scope:
- A `DrawingStore` TCA dependency: load/save a kanji's `PKDrawing` data by id.
- `KanjiWritingFeature` loads the saved drawing on appear and saves on demand.
- `KanjiWritingView` restores the canvas from the saved data and adds a 保存
  button.

Non-goals (follow-on):
- Auto-save (explicit 保存 only); undo/history; per-attempt versioning;
  SwiftData (a file-per-kanji store mirrors the existing `UserStore` JSON
  approach and keeps it testable).

## 3. Components

- **`DrawingStore`** (`@DependencyClient`, in `WritingCanvas`):
  `loadDrawing: @Sendable (_ kanjiID: Int) async -> Data?`,
  `saveDrawing: @Sendable (_ kanjiID: Int, _ data: Data) async -> Void`.
  `liveValue` reads/writes `applicationSupportDirectory/drawings/<id>.drawing`
  (creating the dir); `testValue` is the macro's unimplemented stub. A
  `directory(_:)` factory parameterizes the base dir for the round-trip test.
- **`KanjiWritingFeature`**: `State.savedDrawingData: Data?`; `Action` gains
  `drawingLoaded(Data?)` and `saveDrawing(Data)`. `onAppear` loads stroke paths
  (as today) **and** `drawingStore.loadDrawing(id)` concurrently, emitting
  `drawingLoaded`. `saveDrawing(data)` runs `drawingStore.saveDrawing(id, data)`.
- **`KanjiWritingView`**: keeps the `PKDrawing` in view `@State`. On
  `savedDrawingData` change (initial load), set the canvas drawing via
  `PKDrawing(data:)`. A toolbar 保存 button sends
  `.saveDrawing(drawing.dataRepresentation())`. The existing 消す (clear) and
  guide-toggle buttons stay.

`PKDrawing` is not `Equatable`, so only its `Data` crosses into TCA state — `Data`
is `Equatable`, keeping `State` conformant.

## 4. Testing

- **`DrawingStore`** (round-trip, temp dir): `saveDrawing(id, data)` then
  `loadDrawing(id)` returns the same data; `loadDrawing` of an unsaved id is nil.
- **`KanjiWritingFeature`** (`TestStore`): `onAppear` with a stubbed
  `drawingStore.loadDrawing` → `drawingLoaded(data)` sets `savedDrawingData`;
  `saveDrawing(data)` invokes `drawingStore.saveDrawing` (verified via a
  `LockIsolated` recorder).
- Build verification green; the canvas restore/save round-trip on device is
  manual QA (PKDrawing rendering can't be unit-tested).

## 5. Build order

1. `DrawingStore` dependency (interface + file live) + round-trip test.
2. `KanjiWritingFeature` loads/saves the drawing (extend State/Action/onAppear)
   + feature tests.
3. `KanjiWritingView` restore-on-load + 保存 button (build-verified).

## 6. Follow-on

Auto-save; undo; per-attempt history; thumbnail of saved drawing in the study card.

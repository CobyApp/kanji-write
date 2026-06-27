# Handwriting Recognition (on-device Vision) — Design + Plan

Date: 2026-06-27
Status: Approved (delegated) — combined design + plan. Supersedes the earlier
geometric-heuristic sketch: the user asked for real on-device ML (Apple Vision),
iOS 27 beta acceptable.

## 1. Purpose

After writing, recognize the user's drawn kanji **on-device with Apple's Vision
framework** (Neural Engine) and tell them whether it reads as the target kanji.
A "採点" button rasterizes the drawing, runs Japanese text recognition, and shows
正解 / もう一度 with the recognized candidates.

## 2. Approach (on-device ML)

`PKDrawing` → raster `UIImage`/`CGImage` → Vision `RecognizeTextRequest`
(`recognitionLanguages = [ja]`, `.accurate`) → top candidate strings → matched if
any candidate contains the target literal. All on-device; no network, no server.
Target the newest Vision Swift API (iOS 18+ `RecognizeTextRequest`/
`ImageRequestHandler`), which is available on the iOS 26/27 deployment target.

Recognition accuracy itself is device/manual QA (ML over rendered ink can't be
unit-asserted deterministically); the **dependency boundary** makes the feature
logic testable with a mock recognizer, and a pure candidate-matching helper is
unit-tested.

## 3. Components (in `WritingCanvas`)

- **`RecognitionResult`** (`Equatable, Sendable`): `{ matched: Bool, candidates: [String] }`.
- **`kanjiMatches(target: String, candidates: [String]) -> Bool`** (pure):
  true if any candidate string `contains(target)`. Unit-tested.
- **`KanjiRecognizer`** (`@DependencyClient`):
  `recognize: @Sendable (_ imageData: Data, _ target: String) async -> RecognitionResult`.
  - `liveValue` (on-device, device-QA): decode `imageData` → `CGImage`; run
    `RecognizeTextRequest` with `recognitionLanguages = [Locale.Language(identifier: "ja")]`,
    `recognitionLevel = .accurate`, `usesLanguageCorrection = false`; collect
    `observations.flatMap { $0.topCandidates(3).map(\.string) }`; return
    `RecognitionResult(matched: kanjiMatches(target:candidates:), candidates:)`.
    Failures (bad image / Vision error) → `RecognitionResult(matched: false, candidates: [])`.
  - `testValue` = `@DependencyClient` unimplemented stub.
  - Registered at `DependencyValues.kanjiRecognizer`.
- **`KanjiWritingFeature`**: `State.recognition: RecognitionResult?`;
  `Action.recognize(Data)`; on `.recognize(data)` → run
  `recognizer.recognize(data, state.kanji.literal)` → `Action.recognized(RecognitionResult)`
  → set `state.recognition`. (`@Dependency(\.kanjiRecognizer)`.)
- **`KanjiWritingView`**: a 採点 toolbar button — rasterize the `@State drawing`:
  `drawing.image(from: drawing.bounds (or a fixed square), scale: UIScreen…/2)` →
  `pngData()` → `store.send(.recognize(data))`. Show the result: 正解！ when
  `recognition?.matched`, else もう一度 with the first candidate (if any). Disable
  the button when the drawing is empty.

## 4. Testing

- **`kanjiMatches`**: `kanjiMatches("山", ["山", "川"])` true; `("山", ["川"])`
  false; `("山", ["登山道"])` true (substring); `("山", [])` false.
- **`KanjiWritingFeature`** (`TestStore`, mocked `kanjiRecognizer`):
  `.recognize(data)` with a recognizer returning `RecognitionResult(matched: true,
  candidates: ["山"])` → receives `.recognized(...)` → `state.recognition` set.
- Build green. The live Vision recognition + rasterization + on-screen result are
  device/manual QA (can't unit-test ML on rendered ink).

## 5. Build order

1. `KanjiRecognizer.swift` — `RecognitionResult`, `kanjiMatches`,
   `@DependencyClient KanjiRecognizer` + Vision `liveValue` + DependencyValues +
   `kanjiMatches` unit tests (TDD).
2. `KanjiWritingFeature`: `State.recognition`, `Action.recognize(Data)` +
   `.recognized(RecognitionResult)`, reducer + feature test (mock recognizer).
3. `KanjiWritingView`: rasterize `PKDrawing` → 採点 button → result display
   (build-verified).

No `Project.swift` change (Vision/PencilKit/UIKit are system frameworks; all code
in `WritingCanvas`).

## 6. Non-Goals / Follow-on

Per-stroke order/shape scoring; confidence thresholds/tuning; offline model
bundling; multi-character recognition. This is single-kanji on-device OCR
matching. If recognition proves unreliable on sparse ink in device QA, a
follow-on can add the stroke-count/endpoint heuristic as a fallback signal.

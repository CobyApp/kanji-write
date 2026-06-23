# iPad App Scaffold — Design

Date: 2026-06-23
Status: Approved (brainstorming) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`

## 1. Purpose

Stand up the iPad app (`app/`) as a **minimal working vertical slice** that
proves the whole chosen stack composes: Tuist generates the project, modules
compile, GRDB reads the bundled `kanji.sqlite`, TCA wires a feature end-to-end,
and the slice is unit-testable with `TestStore`.

The slice: **app launches → a `DictionaryClient` reads kanji from the bundled
SQLite via GRDB → a TCA `KanjiListFeature` loads them → SwiftUI renders the
list.** No writing canvas, no study plan, no real screens beyond the list — those
are later sub-projects built on this foundation.

## 2. Scope & Non-Goals

In scope:
- Tuist project (`Project.swift`) with the module targets below.
- TCA feature wiring (`AppFeature` → `KanjiListFeature`) with a `DictionaryClient`
  dependency.
- GRDB-backed live `DictionaryClient` reading a bundled `kanji.sqlite`.
- A **placeholder** `kanji.sqlite` generated from the data-pipeline fixtures
  (2 kanji: 山, 学), bundled as an app resource, to be swapped for the real
  2,136-char DB later.
- `TestStore` unit test for the feature + an integration test for the live client.

Non-goals (this scaffold):
- Writing canvas (PencilKit), study plans, progress/SRS, i18n content rendering,
  DesignSystem, UserStore — added later as their own modules/sub-projects.
- The real full `kanji.sqlite` (needs the follow-on pipeline data plans).
- Device deployment / signing setup beyond what simulator build needs.

## 3. Tooling & platform (verified present)

- Xcode 26.5, Swift 6.3.2 → **deployment target iOS 26** (latest; no
  backward-compat constraint).
- **Tuist 4.155.3** (installed) generates the Xcode project.
- **Swift 6 language mode** with strict concurrency.

## 4. Module layout (Tuist targets, under `app/`)

Single `Project.swift` defining framework targets + one app target. Each module
has one responsibility and a clear interface:

- **`KanjiApp`** (app target) — entry point (`@main App`), hosts `AppFeature`'s
  `Store`. Bundles `kanji.sqlite` as a resource.
- **`AppFeature`** — root TCA reducer; composes child features via `Scope`.
- **`KanjiListFeature`** — list reducer (`State`/`Action`/`body`) + SwiftUI
  `KanjiListView`.
- **`DictionaryClient`** — TCA dependency exposing read-only dictionary access;
  `live` implementation backed by GRDB over the bundled DB; `testValue` returns
  fixed data. This is the architectural seam between UI and data.
- **`SharedModels`** — domain value types (`Kanji`, etc.) shared by client and
  features.

Modules deferred until needed (same pattern when added): `UserStore`,
`WritingCanvas`, `DesignSystem`, and the per-flow feature modules.

Dependency direction: `KanjiApp → AppFeature → KanjiListFeature →
{DictionaryClient, SharedModels}`; `DictionaryClient → SharedModels`. No cycles.

## 5. TCA wiring & data flow

- `AppFeature.State` embeds `KanjiListFeature.State`; `AppFeature.body` uses
  `Scope` to delegate.
- `KanjiListFeature`:
  - `State`: `kanji: IdentifiedArrayOf<Kanji>`, `isLoading: Bool`,
    `loadError: String?`.
  - `Action`: `.onAppear`, `.kanjiResponse(Result<[Kanji], Error>)`.
  - `body`: on `.onAppear` → set `isLoading`, run an `Effect` calling
    `@Dependency(\.dictionaryClient).allKanji()`; on response, populate `kanji`
    or set `loadError`.
- `KanjiListView` observes the store and renders a `List` (literal + readings),
  with loading / error states.
- Reducers stay pure; all I/O is in the injected `DictionaryClient`, so the
  feature is fully testable with `TestStore`.

## 6. DB delivery (placeholder)

- Add a small build step/script that runs the existing data-pipeline `build`
  over the committed fixtures (`kanjidic2_sample.xml`, `jlpt_sample.json`) to
  produce a placeholder `kanji.sqlite` (山, 学), checked into `app/` as a bundled
  resource. It is clearly labeled placeholder.
- `DictionaryClient.live` opens that bundled resource read-only with GRDB and
  maps rows → `SharedModels.Kanji`.
- Swapping in the real DB later is a resource replacement only — no code change.

## 7. Dependencies (Tuist SPM integration)

- `Tuist/Package.swift` declares:
  - **swift-composable-architecture** (TCA, pointfree) — latest.
  - **GRDB.swift** — latest.
- Modules reference them via `.external(name: "ComposableArchitecture")` /
  `.external(name: "GRDB")` in `Project.swift`.

## 8. Testing & verification

- **`KanjiListFeatureTests`**: inject a `DictionaryClient` whose `allKanji`
  returns [山, 学]; drive a `TestStore` through `.onAppear` → assert
  `isLoading` toggles and `kanji` populates; a second test asserts the error
  path sets `loadError`.
- **`DictionaryClientTests`** (integration): point `live` at the placeholder
  bundled DB; assert it returns exactly 2 kanji with expected literals/readings.
- **Build/verify**: `tuist generate` then `xcodebuild` build for an iOS 26
  simulator + run the test bundle. Green build + green tests = scaffold done.
  (Real-iPad run is manual and out of scope here.)

## 9. Build order (within this scaffold)

1. Tuist project + module skeleton + SPM deps → `tuist generate` succeeds, empty
   app builds.
2. `SharedModels.Kanji` + `DictionaryClient` interface (+ `testValue`).
3. `KanjiListFeature` + `TestStore` tests (TDD, against `testValue`).
4. Placeholder `kanji.sqlite` generation + `DictionaryClient.live` (GRDB) +
   integration test.
5. `AppFeature` + `KanjiApp` entry + `KanjiListView`; simulator build green.

The scaffold gets its own implementation plan (spec → plan → build). Later app
features (writing canvas, study plan, progress) are separate sub-projects.

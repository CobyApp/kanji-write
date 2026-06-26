# Stroke-Order Animation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or executing-plans. Steps use checkbox syntax.

**Goal:** Animate a kanji's strokes drawing in order in the study card.

**Architecture:** A `StrokeOrderPlayer` (WritingCanvas) animates KanjiVG paths via a `StrokesShape` whose `animatableData` is overall progress and a pure `strokeFraction` helper. `KanjiDetailFeature` loads stroke paths via the existing `DictionaryClient.strokeOrder`; `KanjiDetailView` shows a 画順 section.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, TCA 1.26. Build/test on iOS 26 iPad sim (UDID from `xcrun simctl list devices available | grep -i ipad`). Run from repo root; `git` from repo root.

Test command shape:
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | tail -12`

---

## Task 1: StrokeOrderPlayer + animation shape (TDD for the helper)

**Files:**
- Create: `app/Sources/WritingCanvas/StrokeOrderPlayer.swift`
- Create: `app/Tests/WritingCanvasTests/StrokeAnimationTests.swift`

- [ ] **Step 1: Write the failing helper test**

Create `app/Tests/WritingCanvasTests/StrokeAnimationTests.swift`:

```swift
import XCTest

@testable import WritingCanvas

final class StrokeAnimationTests: XCTestCase {
    func testStrokeFractionClampsPerStroke() {
        // overall progress 1.5: stroke 0 done, stroke 1 half, stroke 2 not started
        XCTAssertEqual(strokeFraction(progress: 1.5, index: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 1.5, index: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 1.5, index: 2), 0.0, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 0, index: 0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 3, index: 0), 1.0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — `strokeFraction` not found.

- [ ] **Step 3: Implement the player + shape + helper**

Create `app/Sources/WritingCanvas/StrokeOrderPlayer.swift`:

```swift
import SwiftUI

/// Fraction (0...1) of stroke `index` drawn at overall `progress`
/// (progress ranges 0...strokeCount).
func strokeFraction(progress: Double, index: Int) -> Double {
    min(max(progress - Double(index), 0), 1)
}

/// Draws KanjiVG strokes progressively: each stroke completes before the next
/// begins, driven by `progress` (0...strokeCount).
private struct StrokesShape: Shape {
    var progress: Double
    let paths: [String]

    /// KanjiVG strokes are authored in a fixed 109x109 coordinate space.
    private static let viewBoxSize: CGFloat = 109.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.viewBoxSize
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        var combined = Path()
        for (index, d) in paths.enumerated() {
            let fraction = strokeFraction(progress: progress, index: index)
            if fraction <= 0 { continue }
            let full = SVGPath.path(from: SVGPath.parse(d)).applying(transform)
            combined.addPath(fraction >= 1 ? full : full.trimmedPath(from: 0, to: CGFloat(fraction)))
        }
        return combined
    }
}

/// An animated stroke-order display with a replay button.
public struct StrokeOrderPlayer: View {
    private let paths: [String]
    @State private var progress: Double

    public init(paths: [String]) {
        self.paths = paths
        // Start showing the full glyph.
        _progress = State(initialValue: Double(paths.count))
    }

    public var body: some View {
        VStack(spacing: 12) {
            StrokesShape(progress: progress, paths: paths)
                .stroke(Color.primary,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)
                .background(Color(.secondarySystemBackground))
            Button {
                progress = 0
                withAnimation(.easeInOut(duration: Double(paths.count) * 0.5)) {
                    progress = Double(paths.count)
                }
            } label: {
                Label("再生", systemImage: "play.circle")
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **` (helper test passes; the
view compiles).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/WritingCanvas/StrokeOrderPlayer.swift app/Tests/WritingCanvasTests/StrokeAnimationTests.swift
git commit -m "feat(app): animated StrokeOrderPlayer + strokeFraction helper (TDD)"
```

---

## Task 2: KanjiDetailFeature loads stroke paths (TDD)

**Files:**
- Modify: `app/Sources/KanjiDetail/KanjiDetailFeature.swift`
- Modify: `app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift`

- [ ] **Step 1: Update the feature test (failing)**

In `app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift`, in
`testOnAppearLoadsContent`: add a `strokeOrder` stub and the new `.loaded` arg +
state assertion.

Add to `withDependencies`:
```swift
            $0.dictionaryClient.strokeOrder = { _ in ["M10 10", "M20 20", "M30 30"] }
```
Update the `.receive(.loaded(...))` to append `["M10 10", "M20 20", "M30 30"]` as
the final argument, and add to the state mutation closure:
```swift
            $0.strokePaths = ["M10 10", "M20 20", "M30 30"]
```

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — `.loaded` arity / no
`strokePaths`.

- [ ] **Step 3: Extend the reducer**

In `app/Sources/KanjiDetail/KanjiDetailFeature.swift`:

(a) add to `State`: `public var strokePaths: [String] = []`.

(b) extend `loaded` to a 5th argument:
```swift
        case loaded([String: String], [WordEntry], [ExampleSentence], [RelationEntry], [String])
```

(c) in `.onAppear`, add a 5th concurrent load and pass it (keep the
`guard state.glosses.isEmpty` guard):
```swift
                    async let strokes = dictionaryClient.strokeOrder(id)
                    await send(.loaded(
                        (try? await glosses) ?? [:],
                        (try? await words) ?? [],
                        (try? await sentences) ?? [],
                        (try? await relations) ?? [],
                        (try? await strokes) ?? []
                    ))
```

(d) in the `loaded` case, bind and set the 5th value:
```swift
            case let .loaded(glosses, words, sentences, relations, strokePaths):
                ...
                state.relations = relations
                state.strokePaths = strokePaths
                return .none
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/KanjiDetail/KanjiDetailFeature.swift app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift
git commit -m "feat(app): KanjiDetailFeature loads stroke paths"
```

---

## Task 3: 画順 section in the study card

**Files:**
- Modify: `app/Project.swift` (KanjiDetail depends on WritingCanvas)
- Modify: `app/Sources/KanjiDetail/KanjiDetailView.swift`

- [ ] **Step 1: Add the WritingCanvas dependency to KanjiDetail**

In `app/Project.swift`, the `KanjiDetail` target `dependencies` — add
`.target(name: "WritingCanvas")` (alongside SharedModels, DictionaryClient,
ComposableArchitecture). (No cycle: WritingCanvas depends only on
SharedModels/DictionaryClient/TCA.)

- [ ] **Step 2: Add the 画順 section**

In `app/Sources/KanjiDetail/KanjiDetailView.swift`:

(a) add `import WritingCanvas`.

(b) in the `VStack` (after `readings`, before `wordsSection`), add:
```swift
                if !store.strokePaths.isEmpty { strokeOrderSection }
```

(c) add the computed property:
```swift
    private var strokeOrderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("画順").font(.headline)
            StrokeOrderPlayer(paths: store.strokePaths)
        }
    }
```

- [ ] **Step 3: Generate, build, run the full suite**

Run the test command. Expected: `** TEST SUCCEEDED **` — app builds with the
動畫 stroke-order player in the study card; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/Project.swift app/Sources/KanjiDetail/KanjiDetailView.swift
git commit -m "feat(app): animated 画順 section in the study card"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `strokeFraction`/`StrokesShape`/`StrokeOrderPlayer` (spec §3)
  → Task 1; feature loads strokes (§3) → Task 2; 画順 section (§3) → Task 3;
  tests (§4) → Tasks 1–2.
- **Breaking change handled:** `loaded` grows to 5 args; the only caller
  (`onAppear`) and the asserting test are both updated in Task 2.
- **Module graph:** `KanjiDetail → WritingCanvas` added; WritingCanvas does not
  depend on KanjiDetail, so no cycle.
- **Type consistency:** `strokeFraction(progress:index:)`, `StrokeOrderPlayer(paths:)`,
  and the `loaded(_,_,_,_,_)` arity are used identically across tasks.
- **Manual QA:** the animation playback is manual QA; the `strokeFraction` helper
  and the build are automated.

## Follow-on

Step buttons, speed control, stroke numbers, writing-screen integration.

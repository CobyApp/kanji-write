# Writing Canvas (PencilKit) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single-kanji writing screen — a faint KanjiVG stroke-order guide under a pressure-sensitive PencilKit canvas — reachable by tapping a kanji in the list.

**Architecture:** A new `WritingCanvas` static-framework module holds an SVG-path parser (`SVGPath`), a `PKCanvasView` wrapper, the `KanjiWritingFeature` TCA reducer, and its view. `DictionaryClient` gains a `strokeOrder(forKanjiID:)` endpoint (GRDB). `AppFeature` owns a `NavigationStack` path; tapping a kanji pushes the writing feature. The bundled placeholder DB is regenerated to include stroke data.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, PencilKit, TCA 1.26, GRDB 7.11, Tuist 4. App commands run against `app/`; the placeholder-DB step uses the `data-pipeline` venv.

**Spec refinement:** `PKDrawing` is not `Equatable`, so it cannot live in TCA `@ObservableState`. The drawing is therefore **view-local `@State`** and "clear" is a view-local button; `KanjiWritingFeature` state is `{kanji, strokePaths, showGuide}`. This refines spec §3 (which listed `drawing`/`clear` in the reducer).

---

## File Structure (this slice)

```
app/
├── Project.swift                                   # + WritingCanvas + WritingCanvasTests targets; AppFeature dep (modify)
├── Sources/
│   ├── WritingCanvas/
│   │   ├── SVGPath.swift                            # parser + Path builder (new)
│   │   ├── PencilCanvasView.swift                  # PKCanvasView wrapper (new)
│   │   ├── KanjiWritingFeature.swift               # TCA reducer (new)
│   │   └── KanjiWritingView.swift                  # view + guide layer (new)
│   ├── DictionaryClient/
│   │   ├── DictionaryClient.swift                  # + strokeOrder endpoint (modify)
│   │   ├── DictionaryClient+Live.swift             # + GRDB strokeOrder (modify)
│   │   └── Resources/kanji.sqlite                  # regenerated with strokes (modify)
│   ├── KanjiListFeature/
│   │   ├── KanjiListFeature.swift                  # + kanjiTapped action (modify)
│   │   └── KanjiListView.swift                     # rows become buttons; drop own NavigationStack (modify)
│   ├── AppFeature/
│   │   ├── AppFeature.swift                        # + StackState path (modify)
│   │   └── AppView.swift                           # NavigationStack host (new)
│   └── KanjiApp/KanjiApp.swift                     # render AppView (modify)
└── Tests/
    └── WritingCanvasTests/
        ├── SVGPathTests.swift                       # (new)
        └── KanjiWritingFeatureTests.swift           # (new)
```

Verification simulator: an available iPad from `xcrun simctl list devices available | grep -i ipad` (e.g. `iPad Pro 11-inch (M5)`). Test command shape:
`xcodebuild test -workspace app/KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>'`. Run from repo root; `git` from repo root with `app/...` paths.

---

## Task 1: WritingCanvas module + SVGPath parser (TDD)

**Files:**
- Modify: `app/Project.swift`
- Create: `app/Sources/WritingCanvas/SVGPath.swift`
- Create: `app/Tests/WritingCanvasTests/SVGPathTests.swift`

- [ ] **Step 1: Add the module + test target to Project.swift**

In `app/Project.swift`, add two targets to the `targets:` array (after `AppFeature`, before `KanjiApp`), and add `WritingCanvasTests` to the scheme's `testAction`:

```swift
        .target(
            name: "WritingCanvas",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.writingcanvas",
            deploymentTargets: iOS,
            sources: ["Sources/WritingCanvas/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "WritingCanvasTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.writingcanvastests",
            deploymentTargets: iOS,
            sources: ["Tests/WritingCanvasTests/**"],
            dependencies: [.target(name: "WritingCanvas")]
        ),
```

And update the scheme's `testAction` list to include it:

```swift
            testAction: .targets([
                "KanjiListFeatureTests",
                "DictionaryClientTests",
                "WritingCanvasTests",
            ])
```

- [ ] **Step 2: Write the failing parser test**

Create `app/Tests/WritingCanvasTests/SVGPathTests.swift`:

```swift
import CoreGraphics
import XCTest

@testable import WritingCanvas

final class SVGPathTests: XCTestCase {
    func testAbsoluteMoveAndLine() {
        XCTAssertEqual(
            SVGPath.parse("M21,30 L21,70"),
            [.move(CGPoint(x: 21, y: 30)), .line(CGPoint(x: 21, y: 70))])
    }

    func testRelativeCubicResolvesToAbsolute() {
        XCTAssertEqual(
            SVGPath.parse("M0,0 c1,1 2,2 3,3"),
            [.move(.zero),
             .cubic(CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3))])
    }

    func testSmoothCubicReflectsPreviousControl() {
        // After C ... control2=(2,2), end=(3,3); S reflects c1 = 2*end - control2 = (4,4)
        XCTAssertEqual(
            SVGPath.parse("M0,0 C1,1 2,2 3,3 S4,4 5,5"),
            [.move(.zero),
             .cubic(CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)),
             .cubic(CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 4), CGPoint(x: 5, y: 5))])
    }

    func testCloseAndImplicitLineRepeat() {
        XCTAssertEqual(
            SVGPath.parse("M0,0 L1,0 2,0 Z"),
            [.move(.zero), .line(CGPoint(x: 1, y: 0)), .line(CGPoint(x: 2, y: 0)), .close])
    }

    func testUnsupportedCommandIsSkipped() {
        // 'A' (arc) is unsupported; its operands are skipped, the following L still parses.
        XCTAssertEqual(
            SVGPath.parse("M0,0 A1,1 0 0,1 2,2 L3,3"),
            [.move(.zero), .line(CGPoint(x: 3, y: 3))])
    }

    func testPathFromCommandsIsNonEmpty() {
        let path = SVGPath.path(from: SVGPath.parse("M21,30 L21,70"))
        XCTAssertFalse(path.isEmpty)
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: compile failure — `WritingCanvas` / `SVGPath` not found.

- [ ] **Step 4: Implement the parser**

Create `app/Sources/WritingCanvas/SVGPath.swift`:

```swift
import CoreGraphics
import SwiftUI

/// A resolved (absolute-coordinate) SVG path command. KanjiVG uses only these.
public enum SVGCommand: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)  // control1, control2, end
    case close
}

/// Parses KanjiVG path `d` strings into drawable geometry.
/// Supports M/m, L/l, C/c, S/s, Z/z; unsupported commands (A/Q/T/H/V) are skipped.
public enum SVGPath {
    public static func parse(_ d: String) -> [SVGCommand] {
        let chars = Array(d)
        var i = 0
        var commands: [SVGCommand] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var cmd: Character = " "

        func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," ||
                    chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
        }
        func readNumber() -> CGFloat? {
            skipSeparators()
            var s = ""
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
            while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            if i < chars.count, chars[i] == "." {
                s.append(chars[i]); i += 1
                while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                s.append(chars[i]); i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            }
            return Double(s).map { CGFloat($0) }
        }
        func readPoint(relative: Bool) -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < chars.count {
            skipSeparators()
            if i >= chars.count { break }
            if chars[i].isLetter {
                cmd = chars[i]
                i += 1
            } else {
                // Implicit repeat of the previous command; a repeated move becomes a line.
                if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" }
            }
            switch cmd {
            case "M", "m":
                guard let p = readPoint(relative: cmd == "m") else { return commands }
                current = p; subpathStart = p; lastControl = nil
                commands.append(.move(p))
            case "L", "l":
                guard let p = readPoint(relative: cmd == "l") else { return commands }
                current = p; lastControl = nil
                commands.append(.line(p))
            case "C", "c":
                let rel = cmd == "c"
                guard let c1 = readPoint(relative: rel),
                      let c2 = readPoint(relative: rel),
                      let end = readPoint(relative: rel) else { return commands }
                commands.append(.cubic(c1, c2, end)); lastControl = c2; current = end
            case "S", "s":
                let rel = cmd == "s"
                guard let c2 = readPoint(relative: rel),
                      let end = readPoint(relative: rel) else { return commands }
                let c1: CGPoint
                if let lc = lastControl {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c1 = current
                }
                commands.append(.cubic(c1, c2, end)); lastControl = c2; current = end
            case "Z", "z":
                commands.append(.close); current = subpathStart; lastControl = nil
            default:
                // Unsupported command: skip its operands up to the next command letter.
                while i < chars.count, !chars[i].isLetter { i += 1 }
            }
        }
        return commands
    }

    public static func path(from commands: [SVGCommand]) -> Path {
        var path = Path()
        for command in commands {
            switch command {
            case let .move(p): path.move(to: p)
            case let .line(p): path.addLine(to: p)
            case let .cubic(c1, c2, end): path.addCurve(to: end, control1: c1, control2: c2)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` (the 6 SVGPath tests pass; existing tests still pass).

- [ ] **Step 6: Commit**

```bash
git add app/Project.swift app/Sources/WritingCanvas/SVGPath.swift app/Tests/WritingCanvasTests/SVGPathTests.swift
git commit -m "feat(app): WritingCanvas module + SVG path parser (TDD)"
```

---

## Task 2: DictionaryClient.strokeOrder + regenerated DB (TDD)

**Files:**
- Modify: `app/Sources/DictionaryClient/DictionaryClient.swift`
- Modify: `app/Sources/DictionaryClient/DictionaryClient+Live.swift`
- Modify: `app/Sources/DictionaryClient/Resources/kanji.sqlite` (regenerate)
- Modify: `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`

- [ ] **Step 1: Regenerate the placeholder DB with strokes**

Run (from repo root):
```bash
cd data-pipeline && .venv/bin/python -c "from kanjipipe.build_db import build; print(build('tests/fixtures/kanjidic2_sample.xml','tests/fixtures/jlpt_sample.json','tests/fixtures/kanjivg_sample.xml','../app/Sources/DictionaryClient/Resources/kanji.sqlite'))"
```
Expected: prints `{'total': 2, ..., 'missing_stroke_order': 0}`. Verify:
```bash
cd .. && sqlite3 app/Sources/DictionaryClient/Resources/kanji.sqlite "SELECT k.literal, COUNT(*) FROM stroke_order s JOIN kanji k ON s.kanji_id=k.id GROUP BY k.literal;"
```
Expected:
```
学|8
山|3
```

- [ ] **Step 2: Write the failing integration test**

Append to `app/Tests/DictionaryClientTests/DictionaryClientTests.swift` (inside the class):

```swift
    func testLiveReadsStrokeOrderForKanji() async throws {
        let client = DictionaryClient.liveValue
        let all = try await client.allKanji()
        let yama = try XCTUnwrap(all.first { $0.literal == "山" })

        let strokes = try await client.strokeOrder(yama.id)
        XCTAssertEqual(strokes, ["M21,30 L21,70", "M50,20 L50,80", "M79,30 L79,70"])
    }
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: compile failure — `DictionaryClient` has no member `strokeOrder`.

- [ ] **Step 4: Add the endpoint to the interface**

In `app/Sources/DictionaryClient/DictionaryClient.swift`, add the endpoint to the
`@DependencyClient` struct (after `allKanji`):

```swift
    public var strokeOrder: @Sendable (_ kanjiID: Int) async throws -> [String]
```

- [ ] **Step 5: Implement it in the live client**

In `app/Sources/DictionaryClient/DictionaryClient+Live.swift`, add a
`strokeOrder` closure to the `liveValue` initializer (after the `allKanji`
closure — keep `allKanji` exactly as-is, add a comma and the new param):

```swift
        strokeOrder: { kanjiID in
            let queue = try openBundledDatabase()
            return try await queue.read { db in
                try String.fetchAll(db, sql: """
                    SELECT path_d FROM stroke_order
                    WHERE kanji_id = ? ORDER BY ordinal
                    """, arguments: [kanjiID])
            }
        }
```

- [ ] **Step 6: Run it to verify it passes**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` including `testLiveReadsStrokeOrderForKanji`.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/DictionaryClient/DictionaryClient.swift app/Sources/DictionaryClient/DictionaryClient+Live.swift app/Sources/DictionaryClient/Resources/kanji.sqlite app/Tests/DictionaryClientTests/DictionaryClientTests.swift
git commit -m "feat(app): DictionaryClient.strokeOrder endpoint + regenerated placeholder DB"
```

---

## Task 3: KanjiWritingFeature (TDD)

**Files:**
- Create: `app/Sources/WritingCanvas/KanjiWritingFeature.swift`
- Create: `app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift`:

```swift
import ComposableArchitecture
import SharedModels
import XCTest

@testable import WritingCanvas

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class KanjiWritingFeatureTests: XCTestCase {
    func testOnAppearLoadsStrokePaths() async {
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        } withDependencies: {
            $0.dictionaryClient.strokeOrder = { _ in ["d1", "d2", "d3"] }
        }
        await store.send(.onAppear)
        await store.receive(.strokesLoaded(["d1", "d2", "d3"])) {
            $0.strokePaths = ["d1", "d2", "d3"]
        }
    }

    func testToggleGuideFlips() async {
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        }
        await store.send(.toggleGuide) { $0.showGuide = false }
        await store.send(.toggleGuide) { $0.showGuide = true }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: compile failure — `KanjiWritingFeature` not found.

- [ ] **Step 3: Implement the reducer**

Create `app/Sources/WritingCanvas/KanjiWritingFeature.swift`:

```swift
import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct KanjiWritingFeature {
    @ObservableState
    public struct State: Equatable {
        public let kanji: Kanji
        public var strokePaths: [String] = []
        public var showGuide = true
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case strokesLoaded([String])
        case toggleGuide
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let id = state.kanji.id
                return .run { send in
                    let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
                    await send(.strokesLoaded(paths))
                }
            case let .strokesLoaded(paths):
                state.strokePaths = paths
                return .none
            case .toggleGuide:
                state.showGuide.toggle()
                return .none
            }
        }
    }
}
```

> Note: the drawing/clear are handled in the view (`PKDrawing` is not `Equatable`,
> so it cannot live in `@ObservableState`).

- [ ] **Step 4: Run it to verify it passes**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/WritingCanvas/KanjiWritingFeature.swift app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift
git commit -m "feat(app): KanjiWritingFeature loads stroke paths + guide toggle (TDD)"
```

---

## Task 4: PencilCanvasView + KanjiWritingView (build-verified)

**Files:**
- Create: `app/Sources/WritingCanvas/PencilCanvasView.swift`
- Create: `app/Sources/WritingCanvas/KanjiWritingView.swift`

PencilKit ink is manual QA; these are verified by a green build.

- [ ] **Step 1: Implement the PencilKit canvas wrapper**

Create `app/Sources/WritingCanvas/PencilCanvasView.swift`:

```swift
import PencilKit
import SwiftUI

/// Wraps PKCanvasView so SwiftUI/TCA can read and reset the drawing.
/// `.anyInput` lets it work with a finger in the simulator and the Pencil
/// (with pressure/tilt) on device.
public struct PencilCanvasView: UIViewRepresentable {
    @Binding public var drawing: PKDrawing

    public init(drawing: Binding<PKDrawing>) {
        self._drawing = drawing
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 8)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvas.drawing = drawing
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: PencilCanvasView
        init(_ parent: PencilCanvasView) { self.parent = parent }
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
```

- [ ] **Step 2: Implement the writing view + guide layer**

Create `app/Sources/WritingCanvas/KanjiWritingView.swift`:

```swift
import ComposableArchitecture
import PencilKit
import SwiftUI

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled to the square.
private struct GuideStrokesView: View {
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 109.0
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
            }
        }
    }
}

public struct KanjiWritingView: View {
    @Bindable public var store: StoreOf<KanjiWritingFeature>
    @State private var drawing = PKDrawing()

    public init(store: StoreOf<KanjiWritingFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            if store.showGuide {
                GuideStrokesView(paths: store.strokePaths)
            }
            PencilCanvasView(drawing: $drawing)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(.secondarySystemBackground))
        .padding()
        .navigationTitle(store.kanji.literal)
        .toolbar {
            Button(store.showGuide ? "ガイド非表示" : "ガイド表示") {
                store.send(.toggleGuide)
            }
            Button("消す") { drawing = PKDrawing() }
        }
        .task { store.send(.onAppear) }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **` (build + all existing tests still green).

- [ ] **Step 4: Commit**

```bash
git add app/Sources/WritingCanvas/PencilCanvasView.swift app/Sources/WritingCanvas/KanjiWritingView.swift
git commit -m "feat(app): PencilKit canvas wrapper + writing view with stroke guide"
```

---

## Task 5: Navigation wiring

**Files:**
- Modify: `app/Project.swift` (AppFeature depends on WritingCanvas)
- Modify: `app/Sources/KanjiListFeature/KanjiListFeature.swift`
- Modify: `app/Sources/KanjiListFeature/KanjiListView.swift`
- Modify: `app/Sources/AppFeature/AppFeature.swift`
- Create: `app/Sources/AppFeature/AppView.swift`
- Modify: `app/Sources/KanjiApp/KanjiApp.swift`

- [ ] **Step 1: Add the WritingCanvas dependency to AppFeature**

In `app/Project.swift`, the `AppFeature` target's `dependencies` array — add
`.target(name: "WritingCanvas")` so it reads:

```swift
            dependencies: [
                .target(name: "KanjiListFeature"),
                .target(name: "WritingCanvas"),
                .external(name: "ComposableArchitecture"),
            ]
```

- [ ] **Step 2: Add the `kanjiTapped` action to the list feature**

In `app/Sources/KanjiListFeature/KanjiListFeature.swift`, add a case to `Action`
and handle it as a no-op (the parent reacts to it):

Add to the `Action` enum:
```swift
        case kanjiTapped(Kanji)
```
Add to the reducer `switch` (before the closing brace of the switch):
```swift
            case .kanjiTapped:
                return .none
```

- [ ] **Step 3: Make list rows buttons and drop the inner NavigationStack**

Overwrite `app/Sources/KanjiListFeature/KanjiListView.swift`:

```swift
import ComposableArchitecture
import SharedModels
import SwiftUI

public struct KanjiListView: View {
    @Bindable public var store: StoreOf<KanjiListFeature>

    public init(store: StoreOf<KanjiListFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
            } else if let error = store.loadError {
                ContentUnavailableView(
                    "読み込み失敗",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                List(store.kanji) { kanji in
                    Button {
                        store.send(.kanjiTapped(kanji))
                    } label: {
                        HStack(spacing: 16) {
                            Text(kanji.literal)
                                .font(.largeTitle)
                            VStack(alignment: .leading) {
                                Text(kanji.onReadings.joined(separator: "、"))
                                Text(kanji.kunReadings.joined(separator: "、"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("漢字")
        .task { store.send(.onAppear) }
    }
}
```

- [ ] **Step 4: Give AppFeature a navigation stack**

Overwrite `app/Sources/AppFeature/AppFeature.swift`:

```swift
import ComposableArchitecture
import KanjiListFeature
import WritingCanvas

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanjiList = KanjiListFeature.State()
        public var path = StackState<KanjiWritingFeature.State>()
        public init() {}
    }

    public enum Action {
        case kanjiList(KanjiListFeature.Action)
        case path(StackActionOf<KanjiWritingFeature>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.kanjiList, action: \.kanjiList) {
            KanjiListFeature()
        }
        Reduce { state, action in
            switch action {
            case let .kanjiList(.kanjiTapped(kanji)):
                state.path.append(KanjiWritingFeature.State(kanji: kanji))
                return .none
            case .kanjiList, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            KanjiWritingFeature()
        }
    }
}
```

- [ ] **Step 5: Create the navigation host view**

Create `app/Sources/AppFeature/AppView.swift`:

```swift
import ComposableArchitecture
import KanjiListFeature
import SwiftUI
import WritingCanvas

public struct AppView: View {
    @Bindable public var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack(
            path: $store.scope(state: \.path, action: \.path)
        ) {
            KanjiListView(
                store: store.scope(state: \.kanjiList, action: \.kanjiList)
            )
        } destination: { store in
            KanjiWritingView(store: store)
        }
    }
}
```

- [ ] **Step 6: Render AppView from the app entry**

Overwrite `app/Sources/KanjiApp/KanjiApp.swift`:

```swift
import AppFeature
import ComposableArchitecture
import SwiftUI

@main
struct KanjiApp: App {
    @MainActor static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: KanjiApp.store)
        }
    }
}
```

- [ ] **Step 7: Generate, build, and run the full suite**

Run: `cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<iPad>' 2>&1 | tail -12`
Expected: `** TEST SUCCEEDED **` — SVGPath (6), KanjiWritingFeature (2), KanjiListFeature (2), DictionaryClient (2) all pass; the app target builds with the new navigation.

- [ ] **Step 8: Commit**

```bash
git add app/Project.swift app/Sources/KanjiListFeature/KanjiListFeature.swift app/Sources/KanjiListFeature/KanjiListView.swift app/Sources/AppFeature/AppFeature.swift app/Sources/AppFeature/AppView.swift app/Sources/KanjiApp/KanjiApp.swift
git commit -m "feat(app): navigate from kanji list to writing screen (TCA stack)"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `SVGPath` parser (spec §3) → Task 1; `DictionaryClient.strokeOrder`
  + DB regeneration (§4/§7) → Task 2; `KanjiWritingFeature` (§3) → Task 3;
  `PencilCanvasView` + `KanjiWritingView` guide layer (§3) → Task 4; navigation
  (§5) → Task 5; tests (§8) distributed across Tasks 1–3 and the integration test
  in Task 2.
- **Spec refinement recorded:** `drawing`/`clear` are view-local (not in TCA
  state) because `PKDrawing` is not `Equatable`; the reducer state is
  `{kanji, strokePaths, showGuide}`. Tests cover the reducer's real surface.
- **Type consistency:** `SVGCommand` cases, `SVGPath.parse`/`path(from:)`,
  `DictionaryClient.strokeOrder(_ kanjiID: Int)`, `KanjiWritingFeature.Action`
  (`onAppear`/`strokesLoaded`/`toggleGuide`), `KanjiListFeature.Action.kanjiTapped`,
  and `AppFeature` `path`/`StackActionOf` are used consistently across tasks.
- **Module graph:** `WritingCanvas → {SharedModels, DictionaryClient, TCA}`;
  `AppFeature → {KanjiListFeature, WritingCanvas, TCA}`. No cycles. All internal
  modules are `.staticFramework` (consistent with the merged scaffold).
- **Manual QA flagged:** PencilKit ink (pressure, drawing, clear) is verified by
  hand on device/simulator, not unit tests — only the build proves the wrapper
  compiles. Logged here so it isn't mistaken for automated coverage.

## Follow-on (not in this plan)

Stroke-order checking/scoring, drawing persistence (SwiftData `UserStore`),
stroke animation, study plans/SRS, and the real full `kanji.sqlite` — each its
own plan.

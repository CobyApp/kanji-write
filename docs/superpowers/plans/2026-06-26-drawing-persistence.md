# Drawing Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or executing-plans. Checkbox steps.

**Goal:** Save and restore the learner's handwriting per kanji.

**Architecture:** A file-backed `DrawingStore` TCA dependency (load/save `PKDrawing` `Data` by kanji id). `KanjiWritingFeature` loads the saved data on appear (alongside strokes) and saves on a 保存 action. `KanjiWritingView` keeps `PKDrawing` in view `@State`, restores it from the loaded `Data`, and saves the current `Data`.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, PencilKit, TCA 1.26. Build/test on iOS 26 iPad sim (UDID from `xcrun simctl list devices available | grep -i ipad`). Run from repo root; `git` from repo root.

Test command shape:
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | tail -12`

---

## Task 1: DrawingStore dependency (TDD)

**Files:**
- Create: `app/Sources/WritingCanvas/DrawingStore.swift`
- Create: `app/Tests/WritingCanvasTests/DrawingStoreTests.swift`

- [ ] **Step 1: Write the failing round-trip test**

Create `app/Tests/WritingCanvasTests/DrawingStoreTests.swift`:

```swift
import Foundation
import XCTest

@testable import WritingCanvas

final class DrawingStoreTests: XCTestCase {
    func testSaveThenLoadRoundTrips() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "drawings-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DrawingStore.directory(dir)
        let before = await store.loadDrawing(1)
        XCTAssertNil(before)

        let data = Data("ink".utf8)
        await store.saveDrawing(1, data)
        let after = await store.loadDrawing(1)
        XCTAssertEqual(after, data)

        XCTAssertNil(await store.loadDrawing(2))  // unsaved id
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — `DrawingStore` not found.

- [ ] **Step 3: Implement the store**

Create `app/Sources/WritingCanvas/DrawingStore.swift`:

```swift
import ComposableArchitecture
import Foundation

/// Persists a kanji's handwriting (`PKDrawing` data), keyed by kanji id.
@DependencyClient
public struct DrawingStore: Sendable {
    public var loadDrawing: @Sendable (_ kanjiID: Int) async -> Data?
    public var saveDrawing: @Sendable (_ kanjiID: Int, _ data: Data) async -> Void
}

extension DrawingStore {
    /// A store backed by one file per kanji under `directory`.
    public static func directory(_ directory: URL) -> DrawingStore {
        func fileURL(_ kanjiID: Int) -> URL {
            directory.appending(path: "\(kanjiID).drawing")
        }
        return DrawingStore(
            loadDrawing: { kanjiID in try? Data(contentsOf: fileURL(kanjiID)) },
            saveDrawing: { kanjiID, data in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                try? data.write(to: fileURL(kanjiID), options: .atomic)
            }
        )
    }
}

extension DrawingStore: DependencyKey {
    public static let liveValue = DrawingStore.directory(
        URL.applicationSupportDirectory.appending(path: "drawings"))
}

extension DrawingStore: TestDependencyKey {
    public static let testValue = DrawingStore()
}

extension DependencyValues {
    public var drawingStore: DrawingStore {
        get { self[DrawingStore.self] }
        set { self[DrawingStore.self] = newValue }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/WritingCanvas/DrawingStore.swift app/Tests/WritingCanvasTests/DrawingStoreTests.swift
git commit -m "feat(app): DrawingStore dependency (file-per-kanji PKDrawing data, TDD)"
```

---

## Task 2: KanjiWritingFeature loads/saves the drawing (TDD)

**Files:**
- Modify: `app/Sources/WritingCanvas/KanjiWritingFeature.swift`
- Modify: `app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift`

- [ ] **Step 1: Update + add the failing tests**

In `app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift`:

(a) Update `testOnAppearLoadsStrokePaths`: add a `drawingStore.loadDrawing` stub
and receive `drawingLoaded` after `strokesLoaded`. Add to its `withDependencies`:
```swift
            $0.drawingStore.loadDrawing = { _ in nil }
```
and after the existing `await store.receive(.strokesLoaded([...]))` line add:
```swift
        await store.receive(.drawingLoaded(nil))
```
(no state mutation — `savedDrawingData` stays nil).

(b) If `testToggleGuideFlips` calls `.onAppear`, it doesn't — it only sends
`.toggleGuide`, so it needs no `drawingStore` stub. Leave it.

(c) Add two tests:
```swift
    func testOnAppearRestoresSavedDrawing() async {
        let data = Data("saved".utf8)
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        } withDependencies: {
            $0.dictionaryClient.strokeOrder = { _ in [] }
            $0.drawingStore.loadDrawing = { _ in data }
        }
        await store.send(.onAppear)
        await store.receive(.strokesLoaded([]))
        await store.receive(.drawingLoaded(data)) { $0.savedDrawingData = data }
    }

    func testSaveDrawingPersists() async {
        let saved = LockIsolated<(Int, Data)?>(nil)
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        } withDependencies: {
            $0.drawingStore.saveDrawing = { id, data in saved.setValue((id, data)) }
        }
        let data = Data("ink".utf8)
        await store.send(.saveDrawing(data))
        XCTAssertEqual(saved.value?.0, 1)
        XCTAssertEqual(saved.value?.1, data)
    }
```
(`.yama` fixture already exists in this file with `id: 1`; `LockIsolated` comes
from `import ComposableArchitecture`.)

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — no `drawingStore` /
`drawingLoaded` / `saveDrawing` / `savedDrawingData`.

- [ ] **Step 3: Extend the reducer**

In `app/Sources/WritingCanvas/KanjiWritingFeature.swift`:

(a) add to `State`: `public var savedDrawingData: Data?` (after `showGuide`).

(b) add to `Action`:
```swift
        case drawingLoaded(Data?)
        case saveDrawing(Data)
```

(c) add the dependency next to the existing one:
```swift
    @Dependency(\.drawingStore) var drawingStore
```

(d) replace the `.onAppear` effect to load the drawing concurrently with strokes:
```swift
            case .onAppear:
                let id = state.kanji.id
                return .run { send in
                    async let drawingData = drawingStore.loadDrawing(id)
                    do {
                        await send(.strokesLoaded(try await dictionaryClient.strokeOrder(id)))
                    } catch {
                        await send(.strokesLoaded([]))
                    }
                    await send(.drawingLoaded(await drawingData))
                }
```
(keep any existing `guard` at the top of `.onAppear` if present.)

(e) handle the new actions (the `strokesLoaded`/`toggleGuide` cases stay):
```swift
            case let .drawingLoaded(data):
                state.savedDrawingData = data
                return .none
            case let .saveDrawing(data):
                let id = state.kanji.id
                return .run { _ in await drawingStore.saveDrawing(id, data) }
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/WritingCanvas/KanjiWritingFeature.swift app/Tests/WritingCanvasTests/KanjiWritingFeatureTests.swift
git commit -m "feat(app): KanjiWritingFeature loads + saves the kanji's drawing"
```

---

## Task 3: Restore the canvas + 保存 button

**Files:**
- Modify: `app/Sources/WritingCanvas/KanjiWritingView.swift`

- [ ] **Step 1: Restore on load and add the save button**

In `app/Sources/WritingCanvas/KanjiWritingView.swift`:

(a) restore the canvas when the saved data arrives — add to the view body
modifiers (next to `.task`):
```swift
        .onChange(of: store.savedDrawingData) { _, data in
            if let data, let restored = try? PKDrawing(data: data) {
                drawing = restored
            }
        }
```

(b) in the existing `.toolbar`, add a save button alongside the guide-toggle and
消す buttons:
```swift
            Button("保存") { store.send(.saveDrawing(drawing.dataRepresentation())) }
```

- [ ] **Step 2: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` — the app builds; restore
+ save is manual QA.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/WritingCanvas/KanjiWritingView.swift
git commit -m "feat(app): writing canvas restores saved ink + 保存 button"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `DrawingStore` (spec §3) → Task 1; feature load/save (§3) →
  Task 2; view restore + 保存 (§3) → Task 3; tests (§4) across Tasks 1–2.
- **PKDrawing stays out of TCA state:** only `Data?` is in `State` (Equatable);
  `PKDrawing` remains view `@State`, restored via `PKDrawing(data:)`.
- **onAppear change handled:** the existing `testOnAppearLoadsStrokePaths` is
  updated to also receive `.drawingLoaded`; the strokes load keeps its graceful
  `[]`-on-failure behavior.
- **Type consistency:** `DrawingStore.{loadDrawing,saveDrawing,directory}`,
  `Action.{drawingLoaded(Data?),saveDrawing(Data)}`, and `State.savedDrawingData`
  are used identically across tasks.
- **Atomic write:** `saveDrawing` uses `.atomic` to avoid torn files.

## Follow-on

Auto-save on disappear; undo; per-attempt history; a saved-ink thumbnail in the card.

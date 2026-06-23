# iPad App Scaffold — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the iPad app under `app/` as a minimal working vertical slice — Tuist generates the project, TCA wires `AppFeature → KanjiListFeature`, a GRDB-backed `DictionaryClient` reads a bundled placeholder `kanji.sqlite`, and SwiftUI renders the kanji list — all building on an iOS 26 simulator with green `TestStore` and integration tests.

**Architecture:** Tuist `Project.swift` defines framework targets (`SharedModels`, `DictionaryClient`, `KanjiListFeature`, `AppFeature`) + an app target (`KanjiApp`) + two unit-test targets. TCA reducers stay pure; all data I/O is behind the `DictionaryClient` dependency (`@DependencyClient`), whose `live` value uses GRDB to read a bundled SQLite produced by running the existing data-pipeline over its fixtures (山, 学).

**Tech Stack:** Tuist 4, Swift 6 (strict concurrency), iOS 26 target, SwiftUI, The Composable Architecture (TCA), GRDB.swift. All commands run from `app/` unless noted.

---

## File Structure

```
app/
├── Tuist/
│   └── Package.swift                      # SPM deps: TCA, GRDB
├── Project.swift                          # target graph + shared scheme
├── Sources/
│   ├── SharedModels/
│   │   └── Kanji.swift                     # domain value type
│   ├── DictionaryClient/
│   │   ├── DictionaryClient.swift          # @DependencyClient interface + DictionaryError
│   │   ├── DictionaryClient+Live.swift     # GRDB-backed liveValue
│   │   └── Resources/
│   │       └── kanji.sqlite                # placeholder DB (山, 学), bundled resource
│   ├── KanjiListFeature/
│   │   ├── KanjiListFeature.swift          # TCA reducer
│   │   └── KanjiListView.swift             # SwiftUI view
│   ├── AppFeature/
│   │   └── AppFeature.swift                # root reducer composing children
│   └── KanjiApp/
│       └── KanjiApp.swift                  # @main App entry
└── Tests/
    ├── KanjiListFeatureTests/
    │   └── KanjiListFeatureTests.swift     # TestStore unit tests
    └── DictionaryClientTests/
        └── DictionaryClientTests.swift     # live client integration test
```

Each module has one responsibility; `DictionaryClient` is the seam between UI and data.

---

## Task 1: Tuist project skeleton

**Files:**
- Create: `app/Tuist/Package.swift`
- Create: `app/Project.swift`
- Create stub sources: `app/Sources/SharedModels/Kanji.swift`, `app/Sources/DictionaryClient/DictionaryClient.swift`, `app/Sources/KanjiListFeature/KanjiListFeature.swift`, `app/Sources/AppFeature/AppFeature.swift`, `app/Sources/KanjiApp/KanjiApp.swift`
- Create stub tests: `app/Tests/KanjiListFeatureTests/KanjiListFeatureTests.swift`, `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Declare SPM dependencies**

Create `app/Tuist/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "ComposableArchitecture": .framework,
        "GRDB": .framework,
    ]
)
#endif

let package = Package(
    name: "KanjiWrite",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.1"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.0"),
    ]
)
```

> If `tuist install` reports these versions are unavailable for the toolchain, bump each `from:` to the latest tag printed by the resolver and re-run. Do not lower the floor.

- [ ] **Step 2: Define the target graph + shared scheme**

Create `app/Project.swift`:

```swift
import ProjectDescription

private let iOS: DeploymentTargets = .iOS("26.0")

let project = Project(
    name: "KanjiWrite",
    targets: [
        .target(
            name: "SharedModels",
            destinations: [.iPad],
            product: .framework,
            bundleId: "com.cobyapp.kanjiwrite.sharedmodels",
            deploymentTargets: iOS,
            sources: ["Sources/SharedModels/**"]
        ),
        .target(
            name: "DictionaryClient",
            destinations: [.iPad],
            product: .framework,
            bundleId: "com.cobyapp.kanjiwrite.dictionaryclient",
            deploymentTargets: iOS,
            sources: ["Sources/DictionaryClient/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .external(name: "ComposableArchitecture"),
                .external(name: "GRDB"),
            ]
        ),
        .target(
            name: "KanjiListFeature",
            destinations: [.iPad],
            product: .framework,
            bundleId: "com.cobyapp.kanjiwrite.kanjilistfeature",
            deploymentTargets: iOS,
            sources: ["Sources/KanjiListFeature/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "AppFeature",
            destinations: [.iPad],
            product: .framework,
            bundleId: "com.cobyapp.kanjiwrite.appfeature",
            deploymentTargets: iOS,
            sources: ["Sources/AppFeature/**"],
            dependencies: [
                .target(name: "KanjiListFeature"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "KanjiApp",
            destinations: [.iPad],
            product: .app,
            bundleId: "com.cobyapp.kanjiwrite",
            deploymentTargets: iOS,
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": ["UIColorName": ""]
            ]),
            sources: ["Sources/KanjiApp/**"],
            dependencies: [
                .target(name: "AppFeature"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "KanjiListFeatureTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.kanjilistfeaturetests",
            deploymentTargets: iOS,
            sources: ["Tests/KanjiListFeatureTests/**"],
            dependencies: [.target(name: "KanjiListFeature")]
        ),
        .target(
            name: "DictionaryClientTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.dictionaryclienttests",
            deploymentTargets: iOS,
            sources: ["Tests/DictionaryClientTests/**"],
            dependencies: [.target(name: "DictionaryClient")]
        ),
    ],
    schemes: [
        .scheme(
            name: "KanjiWrite",
            shared: true,
            buildAction: .buildAction(targets: ["KanjiApp"]),
            testAction: .targets([
                "KanjiListFeatureTests",
                "DictionaryClientTests",
            ])
        )
    ]
)
```

- [ ] **Step 3: Create compiling stub sources**

Each `sources` glob must match a file. Create minimal valid stubs:

`app/Sources/SharedModels/Kanji.swift`:
```swift
public enum SharedModels {}
```

`app/Sources/DictionaryClient/DictionaryClient.swift`:
```swift
public enum DictionaryClientModule {}
```

`app/Sources/KanjiListFeature/KanjiListFeature.swift`:
```swift
public enum KanjiListFeatureModule {}
```

`app/Sources/AppFeature/AppFeature.swift`:
```swift
public enum AppFeatureModule {}
```

`app/Sources/KanjiApp/KanjiApp.swift`:
```swift
import SwiftUI

@main
struct KanjiApp: App {
    var body: some Scene {
        WindowGroup { Text("scaffold") }
    }
}
```

`app/Tests/KanjiListFeatureTests/KanjiListFeatureTests.swift`:
```swift
import XCTest

final class KanjiListFeatureScaffoldTests: XCTestCase {
    func testScaffold() { XCTAssertTrue(true) }
}
```

`app/Tests/DictionaryClientTests/DictionaryClientTests.swift`:
```swift
import XCTest

final class DictionaryClientScaffoldTests: XCTestCase {
    func testScaffold() { XCTAssertTrue(true) }
}
```

- [ ] **Step 4: Ignore Tuist/Xcode generated artifacts**

Append to `.gitignore` (repo root):
```
# Tuist / Xcode generated (manifests are committed; generated projects are not)
app/*.xcodeproj
app/*.xcworkspace
app/Derived/
app/Tuist/.build/
app/.build/
```

- [ ] **Step 5: Generate and build the empty app**

Run:
```bash
cd app && tuist install && tuist generate --no-open
```
Expected: resolves TCA + GRDB, writes `KanjiWrite.xcworkspace`, exits 0.

Then list an available iPad simulator and build:
```bash
xcrun simctl list devices available | grep -i ipad
xcodebuild -workspace app/KanjiWrite.xcworkspace -scheme KanjiWrite \
  -destination 'platform=iOS Simulator,name=<an available iPad from the list above>' \
  build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add app/Tuist/Package.swift app/Project.swift app/Sources app/Tests .gitignore
git commit -m "chore(app): Tuist project skeleton (TCA + GRDB, iOS 26 targets)"
```

---

## Task 2: SharedModels.Kanji

**Files:**
- Modify: `app/Sources/SharedModels/Kanji.swift`

This is a plain value type with no behavior; it is exercised by the
`KanjiListFeature` and `DictionaryClient` tests in later tasks, so it gets no
dedicated test of its own.

- [ ] **Step 1: Replace the stub with the model**

Overwrite `app/Sources/SharedModels/Kanji.swift`:

```swift
import Foundation

/// A single kanji as shown in study screens. Pure value type — no persistence
/// or framework coupling.
public struct Kanji: Equatable, Identifiable, Sendable {
    public let id: Int
    public let literal: String
    public let strokeCount: Int
    public let grade: Int?
    public let jlptLevel: String?
    public let onReadings: [String]
    public let kunReadings: [String]

    public init(
        id: Int,
        literal: String,
        strokeCount: Int,
        grade: Int?,
        jlptLevel: String?,
        onReadings: [String],
        kunReadings: [String]
    ) {
        self.id = id
        self.literal = literal
        self.strokeCount = strokeCount
        self.grade = grade
        self.jlptLevel = jlptLevel
        self.onReadings = onReadings
        self.kunReadings = kunReadings
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/SharedModels/Kanji.swift
git commit -m "feat(app): SharedModels.Kanji domain value type"
```

---

## Task 3: DictionaryClient interface

**Files:**
- Modify: `app/Sources/DictionaryClient/DictionaryClient.swift`

- [ ] **Step 1: Replace the stub with the dependency interface**

Overwrite `app/Sources/DictionaryClient/DictionaryClient.swift`:

```swift
import ComposableArchitecture
import SharedModels

/// Errors surfaced by the dictionary data layer.
public enum DictionaryError: Error, Equatable {
    case databaseUnavailable
    case query(String)
}

/// Read-only access to the bundled kanji dictionary. The single seam between
/// UI/features and the data layer; `liveValue` (added later) is GRDB-backed.
@DependencyClient
public struct DictionaryClient: Sendable {
    public var allKanji: @Sendable () async throws -> [Kanji]
}

extension DictionaryClient: TestDependencyKey {
    public static let testValue = DictionaryClient()
}

extension DependencyValues {
    public var dictionaryClient: DictionaryClient {
        get { self[DictionaryClient.self] }
        set { self[DictionaryClient.self] = newValue }
    }
}
```

> `@DependencyClient` synthesizes `testValue`'s endpoints to fail if called
> unimplemented; tests override `allKanji` explicitly. `liveValue` is added in
> Task 5.

- [ ] **Step 2: Verify it compiles**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/DictionaryClient/DictionaryClient.swift
git commit -m "feat(app): DictionaryClient dependency interface + DictionaryError"
```

---

## Task 4: KanjiListFeature (TDD)

**Files:**
- Modify: `app/Sources/KanjiListFeature/KanjiListFeature.swift`
- Modify: `app/Tests/KanjiListFeatureTests/KanjiListFeatureTests.swift`

- [ ] **Step 1: Write the failing tests**

Overwrite `app/Tests/KanjiListFeatureTests/KanjiListFeatureTests.swift`:

```swift
import ComposableArchitecture
import SharedModels
import XCTest

@testable import KanjiListFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
    static let gaku = Kanji(id: 2, literal: "学", strokeCount: 8, grade: 1,
                            jlptLevel: "N5", onReadings: ["ガク"], kunReadings: ["まな.ぶ"])
}

@MainActor
final class KanjiListFeatureTests: XCTestCase {
    func testOnAppearLoadsKanji() async {
        let store = TestStore(initialState: KanjiListFeature.State()) {
            KanjiListFeature()
        } withDependencies: {
            $0.dictionaryClient.allKanji = { [.yama, .gaku] }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(.kanjiLoaded([.yama, .gaku])) {
            $0.isLoading = false
            $0.kanji = [.yama, .gaku]
        }
    }

    func testOnAppearFailureSetsError() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let store = TestStore(initialState: KanjiListFeature.State()) {
            KanjiListFeature()
        } withDependencies: {
            $0.dictionaryClient.allKanji = { throw Boom() }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(.loadFailed("boom")) {
            $0.isLoading = false
            $0.loadError = "boom"
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' 2>&1 | tail -8
```
Expected: compile failure — `KanjiListFeature` has no `State`/`Action`/reducer yet.

- [ ] **Step 3: Implement the reducer**

Overwrite `app/Sources/KanjiListFeature/KanjiListFeature.swift`:

```swift
import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct KanjiListFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var isLoading = false
        public var loadError: String?
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case kanjiLoaded([Kanji])
        case loadFailed(String)
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.loadError = nil
                return .run { send in
                    do {
                        await send(.kanjiLoaded(try await dictionaryClient.allKanji()))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
            case let .kanjiLoaded(kanji):
                state.isLoading = false
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                return .none
            case let .loadFailed(message):
                state.isLoading = false
                state.loadError = message
                return .none
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' 2>&1 | tail -8
```
Expected: `TEST SUCCEEDED` for the two `KanjiListFeatureTests`. (The `DictionaryClientScaffoldTests` stub still passes.)

- [ ] **Step 5: Commit**

```bash
git add app/Sources/KanjiListFeature/KanjiListFeature.swift app/Tests/KanjiListFeatureTests/KanjiListFeatureTests.swift
git commit -m "feat(app): KanjiListFeature reducer with load success/failure (TDD)"
```

---

## Task 5: Placeholder DB + live DictionaryClient (TDD)

**Files:**
- Create: `app/Sources/DictionaryClient/Resources/kanji.sqlite` (generated binary)
- Create: `app/Sources/DictionaryClient/DictionaryClient+Live.swift`
- Modify: `app/Project.swift` (add the resources glob to the `DictionaryClient` target)
- Modify: `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`

- [ ] **Step 1: Generate the placeholder DB from the pipeline fixtures**

Run (from repo root):
```bash
mkdir -p app/Sources/DictionaryClient/Resources
cd data-pipeline && .venv/bin/python -c "from kanjipipe.build_db import build; print(build('tests/fixtures/kanjidic2_sample.xml','tests/fixtures/jlpt_sample.json','../app/Sources/DictionaryClient/Resources/kanji.sqlite'))"
```
Expected: prints a report like `{'total': 2, 'missing_reading': 0, 'missing_en': 0, 'missing_grade': 0}` and writes the file. Verify:
```bash
cd .. && sqlite3 app/Sources/DictionaryClient/Resources/kanji.sqlite "SELECT literal FROM kanji ORDER BY id;"
```
Expected output:
```
山
学
```

- [ ] **Step 2: Add the resource to the DictionaryClient target**

In `app/Project.swift`, change the `DictionaryClient` target so it includes the
resources glob. Replace its target block with:

```swift
        .target(
            name: "DictionaryClient",
            destinations: [.iPad],
            product: .framework,
            bundleId: "com.cobyapp.kanjiwrite.dictionaryclient",
            deploymentTargets: iOS,
            sources: ["Sources/DictionaryClient/**"],
            resources: ["Sources/DictionaryClient/Resources/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .external(name: "ComposableArchitecture"),
                .external(name: "GRDB"),
            ]
        ),
```

> Note: the `sources` glob is `Sources/DictionaryClient/**`. Tuist excludes
> declared resource files from compilation, so the `.sqlite` under `Resources/`
> is bundled, not compiled.

- [ ] **Step 3: Write the failing integration test**

Overwrite `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`:

```swift
import XCTest

@testable import DictionaryClient

final class DictionaryClientTests: XCTestCase {
    func testLiveReadsBundledKanji() async throws {
        let client = DictionaryClient.liveValue
        let kanji = try await client.allKanji()

        XCTAssertEqual(kanji.map(\.literal), ["山", "学"])

        let yama = try XCTUnwrap(kanji.first { $0.literal == "山" })
        XCTAssertEqual(yama.strokeCount, 3)
        XCTAssertEqual(yama.jlptLevel, "N5")
        XCTAssertTrue(yama.onReadings.contains("サン"))
        XCTAssertTrue(yama.kunReadings.contains("やま"))
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' 2>&1 | tail -8
```
Expected: compile failure — `DictionaryClient.liveValue` does not exist yet.

- [ ] **Step 5: Implement the GRDB-backed live client**

Create `app/Sources/DictionaryClient/DictionaryClient+Live.swift`:

```swift
import ComposableArchitecture
import Foundation
import GRDB
import SharedModels

extension DictionaryClient: DependencyKey {
    public static let liveValue = DictionaryClient(
        allKanji: {
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [Kanji] in
                let kanjiRows = try Row.fetchAll(db, sql: """
                    SELECT id, literal, stroke_count, grade, jlpt_level
                    FROM kanji
                    ORDER BY id
                    """)
                return try kanjiRows.map { row in
                    let id: Int = row["id"]
                    let grade: Int? = row["grade"]
                    let jlpt: String? = row["jlpt_level"]

                    let readingRows = try Row.fetchAll(db, sql: """
                        SELECT lang_axis, value FROM reading
                        WHERE kanji_id = ? AND lang_axis IN ('on', 'kun')
                        """, arguments: [id])

                    var onReadings: [String] = []
                    var kunReadings: [String] = []
                    for r in readingRows {
                        let axis: String = r["lang_axis"]
                        let value: String = r["value"]
                        if axis == "on" { onReadings.append(value) }
                        else { kunReadings.append(value) }
                    }

                    return Kanji(
                        id: id,
                        literal: row["literal"],
                        strokeCount: row["stroke_count"],
                        grade: grade,
                        jlptLevel: jlpt,
                        onReadings: onReadings,
                        kunReadings: kunReadings
                    )
                }
            }
        }
    )

    /// Opens the placeholder dictionary DB bundled with this module, read-only.
    static func openBundledDatabase() throws -> DatabaseQueue {
        guard let url = Bundle.module.url(forResource: "kanji", withExtension: "sqlite") else {
            throw DictionaryError.databaseUnavailable
        }
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: url.path, configuration: config)
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' 2>&1 | tail -8
```
Expected: all tests pass, including `testLiveReadsBundledKanji`.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/DictionaryClient/Resources/kanji.sqlite app/Sources/DictionaryClient/DictionaryClient+Live.swift app/Project.swift app/Tests/DictionaryClientTests/DictionaryClientTests.swift
git commit -m "feat(app): GRDB-backed live DictionaryClient + bundled placeholder DB"
```

---

## Task 6: AppFeature + view + app entry

**Files:**
- Modify: `app/Sources/AppFeature/AppFeature.swift`
- Create: `app/Sources/KanjiListFeature/KanjiListView.swift`
- Modify: `app/Sources/KanjiApp/KanjiApp.swift`

- [ ] **Step 1: Implement the root reducer**

Overwrite `app/Sources/AppFeature/AppFeature.swift`:

```swift
import ComposableArchitecture
import KanjiListFeature

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanjiList = KanjiListFeature.State()
        public init() {}
    }

    public enum Action {
        case kanjiList(KanjiListFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.kanjiList, action: \.kanjiList) {
            KanjiListFeature()
        }
    }
}
```

- [ ] **Step 2: Implement the list view**

Create `app/Sources/KanjiListFeature/KanjiListView.swift`:

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
        NavigationStack {
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
                }
            }
            .navigationTitle("漢字")
            .task { store.send(.onAppear) }
        }
    }
}
```

- [ ] **Step 3: Wire the app entry to the store**

Overwrite `app/Sources/KanjiApp/KanjiApp.swift`:

```swift
import AppFeature
import ComposableArchitecture
import KanjiListFeature
import SwiftUI

@main
struct KanjiApp: App {
    @MainActor static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            KanjiListView(
                store: KanjiApp.store.scope(state: \.kanjiList, action: \.kanjiList)
            )
        }
    }
}
```

- [ ] **Step 4: Generate, build, and run the full test suite**

Run:
```bash
cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace \
  -scheme KanjiWrite -destination 'platform=iOS Simulator,name=<available iPad>' 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **` — `KanjiListFeatureTests` (2) and `DictionaryClientTests` (1) all pass, and the app target builds.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/AppFeature/AppFeature.swift app/Sources/KanjiListFeature/KanjiListView.swift app/Sources/KanjiApp/KanjiApp.swift
git commit -m "feat(app): AppFeature composition + KanjiListView + app entry"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** module layout (spec §4) → Task 1; `SharedModels.Kanji` (§4) →
  Task 2; `DictionaryClient` seam (§4/§5) → Task 3 (interface) + Task 5 (live);
  TCA wiring `AppFeature → KanjiListFeature` (§5) → Tasks 4 & 6; placeholder DB
  from fixtures (§6) → Task 5; SPM deps via Tuist (§7) → Task 1; TestStore +
  integration tests + simulator build verification (§8) → Tasks 4, 5, 6.
- **Deferred-by-spec (not defects):** UserStore, WritingCanvas, DesignSystem, and
  later feature flows are explicitly out of scope (spec §2) and have no tasks.
- **Type consistency:** `DictionaryClient.allKanji: () async throws -> [Kanji]`,
  `Kanji` field names (`literal`, `strokeCount`, `grade`, `jlptLevel`,
  `onReadings`, `kunReadings`), and `KanjiListFeature.Action`
  (`onAppear`/`kanjiLoaded`/`loadFailed`) are used identically across Tasks 2–6.
- **Version risk:** TCA/GRDB `from:` floors and the iPad simulator name may need
  adjustment for the installed toolchain; Task 1 Step 1 and the `<available iPad>`
  placeholder in every `-destination` flag tell the implementer how to resolve
  these against `tuist install` / `xcrun simctl list` output. These are runtime
  lookups, not unspecified code.

## Follow-on (not in this plan)

Real full `kanji.sqlite` (pipeline data plans), writing canvas (PencilKit),
study plans, progress/SRS, DesignSystem, and i18n content rendering — each its
own sub-project (spec → plan → build) on top of this scaffold.

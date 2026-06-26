# Study Card (Kanji Detail) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping a kanji opens a study card (Korean 훈음 meaning, readings, usage words, example sentences) with a button into the writing canvas; ship the full enriched 2,136-kanji DB.

**Architecture:** Re-bundle the enriched `kanji.sqlite`. Add `glosses`/`words`/`sentences` endpoints to `DictionaryClient` (+ GRDB live) and `WordEntry`/`ExampleSentence` to `SharedModels`. A new `KanjiDetail` module holds `KanjiDetailFeature`/`KanjiDetailView`. The nav stacks switch from holding `KanjiWritingFeature.State` to a `Path` `@Reducer` enum (`.detail` / `.writing`): tap → push `.detail`, the card's write button → push `.writing`.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, TCA 1.26, GRDB 7.11, Tuist 4. Build/test on an iOS 26 iPad simulator (id from `xcrun simctl list devices available | grep -i ipad`, e.g. `iPad Pro 11-inch (M5)` — pin by UDID if the name is ambiguous). Run from repo root; `git` from repo root; never stage `*.xcworkspace`/`Derived/`.

Test command shape:
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | tail -14`

---

## File Structure (this slice)

```
app/
├── Project.swift                                  # + KanjiDetail + KanjiDetailTests; AppFeature dep (modify)
├── Sources/
│   ├── DictionaryClient/
│   │   ├── DictionaryClient.swift                 # + glosses/words/sentences endpoints (modify)
│   │   ├── DictionaryClient+Live.swift            # + GRDB impls (modify)
│   │   └── Resources/kanji.sqlite                 # re-bundled enriched DB (modify)
│   ├── SharedModels/
│   │   └── KanjiContent.swift                      # WordEntry + ExampleSentence (new)
│   ├── KanjiDetail/
│   │   ├── KanjiDetailFeature.swift                # TCA reducer (new)
│   │   └── KanjiDetailView.swift                   # view (new)
│   └── AppFeature/
│       ├── Path.swift                              # Destination @Reducer enum (new)
│       ├── AppFeature.swift                        # path uses Path; tap→detail, write→writing (modify)
│       ├── AppView.swift                           # destination switches on Path (modify)
│       ├── RootFeature.swift                       # planPath uses Path (modify)
│       └── RootView.swift                          # plan destination switches on Path (modify)
└── Tests/
    └── KanjiDetailTests/
        └── KanjiDetailFeatureTests.swift           # (new)
```

---

## Task 1: Re-bundle the enriched DB

**Files:**
- Modify: `app/Sources/DictionaryClient/Resources/kanji.sqlite`

- [ ] **Step 1: Copy the enriched build over the placeholder**

The full enriched DB exists at `data-pipeline/out/kanji.sqlite` (2,136 kanji with
glosses/words/sentences/relations). Run (from repo root):
```bash
cp data-pipeline/out/kanji.sqlite app/Sources/DictionaryClient/Resources/kanji.sqlite
sqlite3 app/Sources/DictionaryClient/Resources/kanji.sqlite \
  "SELECT (SELECT COUNT(*) FROM kanji), (SELECT COUNT(*) FROM gloss WHERE lang='ko'), (SELECT COUNT(*) FROM word), (SELECT COUNT(*) FROM sentence);"
```
Expected: `2136|2136|<~25000>|<~5000>`.

> If `data-pipeline/out/kanji.sqlite` is absent (fresh checkout), rebuild it:
> `cd data-pipeline && .venv/bin/python -m kanjipipe.build_db --out out/kanji.sqlite`
> (requires `sources/` fetched + the committed `sources/llm_glosses.jsonl`).

- [ ] **Step 2: Verify the existing suite still passes**

Run the test command. Expected: `** TEST SUCCEEDED **` — the existing
`DictionaryClientTests` (count == 2136, 山 strokeCount 3) still hold against the
enriched superset DB; all other tests unaffected.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/DictionaryClient/Resources/kanji.sqlite
git commit -m "feat(app): bundle full enriched kanji.sqlite (glosses/words/sentences)"
```

---

## Task 2: SharedModels content types + DictionaryClient endpoints (TDD)

**Files:**
- Create: `app/Sources/SharedModels/KanjiContent.swift`
- Modify: `app/Sources/DictionaryClient/DictionaryClient.swift`
- Modify: `app/Sources/DictionaryClient/DictionaryClient+Live.swift`
- Modify: `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`

- [ ] **Step 1: Add the content models**

Create `app/Sources/SharedModels/KanjiContent.swift`:

```swift
import Foundation

/// A usage word that contains a kanji (from JMdict).
public struct WordEntry: Equatable, Identifiable, Sendable {
    public let id: Int
    public let surface: String
    public let reading: String
    public let meaningEn: String?

    public init(id: Int, surface: String, reading: String, meaningEn: String?) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.meaningEn = meaningEn
    }
}

/// A Japanese example sentence with translations keyed by language code.
public struct ExampleSentence: Equatable, Identifiable, Sendable {
    public let id: Int
    public let textJa: String
    public let translations: [String: String]

    public init(id: Int, textJa: String, translations: [String: String]) {
        self.id = id
        self.textJa = textJa
        self.translations = translations
    }
}
```

- [ ] **Step 2: Write the failing integration tests**

Append to `app/Tests/DictionaryClientTests/DictionaryClientTests.swift` (inside the class):

```swift
    func testLiveReadsGlossesForKanji() async throws {
        let client = DictionaryClient.liveValue
        let yama = try XCTUnwrap(try await client.allKanji().first { $0.literal == "山" })
        let glosses = try await client.glosses(yama.id)
        XCTAssertEqual(glosses["ko"], "메 산")
        XCTAssertNotNil(glosses["en"])
        XCTAssertNotNil(glosses["ja"])
        XCTAssertNotNil(glosses["zh"])
    }

    func testLiveReadsWordsAndSentencesForKanji() async throws {
        let client = DictionaryClient.liveValue
        let yama = try XCTUnwrap(try await client.allKanji().first { $0.literal == "山" })

        let words = try await client.words(yama.id, 12)
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.allSatisfy { !$0.surface.isEmpty && !$0.reading.isEmpty })

        let sentences = try await client.sentences(yama.id, 3)
        XCTAssertFalse(sentences.isEmpty)
        XCTAssertTrue(sentences[0].textJa.contains("山"))
        XCTAssertFalse(sentences[0].translations.isEmpty)
    }
```

- [ ] **Step 3: Run to verify it fails**

Run the test command. Expected: compile failure — `DictionaryClient` has no
`glosses`/`words`/`sentences`.

- [ ] **Step 4: Add the endpoints to the interface**

In `app/Sources/DictionaryClient/DictionaryClient.swift`, add to the
`@DependencyClient` struct (after the existing endpoints):

```swift
    public var glosses: @Sendable (_ kanjiID: Int) async throws -> [String: String]
    public var words: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [WordEntry]
    public var sentences: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [ExampleSentence]
```

- [ ] **Step 5: Implement them in the live client**

In `app/Sources/DictionaryClient/DictionaryClient+Live.swift`, add three closures
to the `liveValue` initializer (after the existing `allKanji`/`strokeOrder`
closures — keep those unchanged, add commas and the new params):

```swift
        glosses: { kanjiID in
            let queue = try openBundledDatabase()
            return try await queue.read { db in
                var result: [String: String] = [:]
                for row in try Row.fetchAll(
                    db, sql: "SELECT lang, text FROM gloss WHERE kanji_id = ?",
                    arguments: [kanjiID]
                ) {
                    let lang: String = row["lang"]
                    result[lang] = row["text"]
                }
                return result
            }
        },
        words: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [WordEntry] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT w.id, w.surface, w.reading_kana FROM word w
                    JOIN word_kanji wk ON wk.word_id = w.id
                    WHERE wk.kanji_id = ?
                    ORDER BY w.is_common DESC, w.id
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    let meaning = try String.fetchOne(
                        db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = 'en' LIMIT 1",
                        arguments: [id])
                    return WordEntry(
                        id: id, surface: row["surface"],
                        reading: row["reading_kana"], meaningEn: meaning)
                }
            }
        },
        sentences: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [ExampleSentence] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.text_ja FROM sentence s
                    JOIN sentence_kanji sk ON sk.sentence_id = s.id
                    WHERE sk.kanji_id = ?
                    ORDER BY s.id
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    var translations: [String: String] = [:]
                    for tr in try Row.fetchAll(
                        db, sql: "SELECT lang, text FROM sentence_translation WHERE sentence_id = ?",
                        arguments: [id]
                    ) {
                        let lang: String = tr["lang"]
                        translations[lang] = tr["text"]
                    }
                    return ExampleSentence(
                        id: id, textJa: row["text_ja"], translations: translations)
                }
            }
        }
```

- [ ] **Step 6: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **` including the two new
DictionaryClient tests.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/SharedModels/KanjiContent.swift app/Sources/DictionaryClient/DictionaryClient.swift app/Sources/DictionaryClient/DictionaryClient+Live.swift app/Tests/DictionaryClientTests/DictionaryClientTests.swift
git commit -m "feat(app): DictionaryClient glosses/words/sentences endpoints + content models"
```

---

## Task 3: KanjiDetail module — feature + view (TDD)

**Files:**
- Modify: `app/Project.swift`
- Create: `app/Sources/KanjiDetail/KanjiDetailFeature.swift`
- Create: `app/Sources/KanjiDetail/KanjiDetailView.swift`
- Create: `app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift`

- [ ] **Step 1: Add the module + test target to Project.swift**

In `app/Project.swift`, add two targets (after `StudyPlan`, before `KanjiApp`)
and add `KanjiDetailTests` to the scheme `testAction`:

```swift
        .target(
            name: "KanjiDetail",
            destinations: [.iPad],
            product: .staticFramework,
            bundleId: "com.cobyapp.kanjiwrite.kanjidetail",
            deploymentTargets: iOS,
            sources: ["Sources/KanjiDetail/**"],
            dependencies: [
                .target(name: "SharedModels"),
                .target(name: "DictionaryClient"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "KanjiDetailTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.kanjidetailtests",
            deploymentTargets: iOS,
            sources: ["Tests/KanjiDetailTests/**"],
            dependencies: [.target(name: "KanjiDetail")]
        ),
```
testAction list adds `"KanjiDetailTests"`.

- [ ] **Step 2: Write the failing feature tests**

Create `app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift`:

```swift
import ComposableArchitecture
import SharedModels
import XCTest

@testable import KanjiDetail

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class KanjiDetailFeatureTests: XCTestCase {
    func testOnAppearLoadsContent() async {
        let store = TestStore(initialState: KanjiDetailFeature.State(kanji: .yama)) {
            KanjiDetailFeature()
        } withDependencies: {
            $0.dictionaryClient.glosses = { _ in ["ko": "메 산", "en": "mountain"] }
            $0.dictionaryClient.words = { _, _ in
                [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")]
            }
            $0.dictionaryClient.sentences = { _, _ in
                [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])]
            }
        }
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(
            .loaded(["ko": "메 산", "en": "mountain"],
                    [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")],
                    [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])])
        ) {
            $0.isLoading = false
            $0.glosses = ["ko": "메 산", "en": "mountain"]
            $0.words = [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")]
            $0.sentences = [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])]
        }
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run the test command. Expected: compile failure — `KanjiDetailFeature` not found.

- [ ] **Step 4: Implement the reducer**

Create `app/Sources/KanjiDetail/KanjiDetailFeature.swift`:

```swift
import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct KanjiDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public let kanji: Kanji
        public var glosses: [String: String] = [:]
        public var words: IdentifiedArrayOf<WordEntry> = []
        public var sentences: [ExampleSentence] = []
        public var isLoading = false
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([String: String], [WordEntry], [ExampleSentence])
        case writeTapped
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                let id = state.kanji.id
                return .run { send in
                    async let glosses = dictionaryClient.glosses(id)
                    async let words = dictionaryClient.words(id, 12)
                    async let sentences = dictionaryClient.sentences(id, 3)
                    await send(.loaded(
                        (try? await glosses) ?? [:],
                        (try? await words) ?? [],
                        (try? await sentences) ?? []
                    ))
                }
            case let .loaded(glosses, words, sentences):
                state.isLoading = false
                state.glosses = glosses
                state.words = IdentifiedArray(uniqueElements: words)
                state.sentences = sentences
                return .none
            case .writeTapped:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Implement the view**

Create `app/Sources/KanjiDetail/KanjiDetailView.swift`:

```swift
import ComposableArchitecture
import SharedModels
import SwiftUI

public struct KanjiDetailView: View {
    @Bindable public var store: StoreOf<KanjiDetailFeature>

    public init(store: StoreOf<KanjiDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                readings
                if !store.words.isEmpty { wordsSection }
                if !store.sentences.isEmpty { sentencesSection }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(store.kanji.literal)
        .toolbar {
            Button("書いて練習") { store.send(.writeTapped) }
        }
        .task { store.send(.onAppear) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(store.kanji.literal)
                .font(.system(size: 84))
            VStack(alignment: .leading, spacing: 8) {
                Text(store.glosses["ko"] ?? "")
                    .font(.title)
                HStack(spacing: 8) {
                    chip("\(store.kanji.grade.map { "学\($0)" } ?? "")")
                    if let jlpt = store.kanji.jlptLevel { chip(jlpt) }
                }
            }
            Spacer()
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .opacity(text.isEmpty ? 0 : 1)
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("読み").font(.headline)
            Text("音 " + store.kanji.onReadings.joined(separator: "、"))
            Text("訓 " + store.kanji.kunReadings.joined(separator: "、"))
                .foregroundStyle(.secondary)
        }
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活用").font(.headline)
            ForEach(store.words) { word in
                VStack(alignment: .leading) {
                    Text("\(word.surface)（\(word.reading)）").font(.body)
                    if let meaning = word.meaningEn {
                        Text(meaning).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("例文").font(.headline)
            ForEach(store.sentences) { sentence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence.textJa)
                    if let ko = sentence.translations["ko"] {
                        Text(ko).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 7: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` (build + tests green).

- [ ] **Step 8: Commit**

```bash
git add app/Project.swift app/Sources/KanjiDetail/KanjiDetailFeature.swift app/Sources/KanjiDetail/KanjiDetailView.swift app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift
git commit -m "feat(app): KanjiDetail study-card feature + view (TDD)"
```

---

## Task 4: Navigation — tap → study card → write

**Files:**
- Modify: `app/Project.swift` (AppFeature depends on KanjiDetail)
- Create: `app/Sources/AppFeature/Path.swift`
- Modify: `app/Sources/AppFeature/AppFeature.swift`
- Modify: `app/Sources/AppFeature/AppView.swift`
- Modify: `app/Sources/AppFeature/RootFeature.swift`
- Modify: `app/Sources/AppFeature/RootView.swift`

- [ ] **Step 1: Add the KanjiDetail dependency to AppFeature**

In `app/Project.swift`, the `AppFeature` target `dependencies` — add
`.target(name: "KanjiDetail")` (alongside `KanjiListFeature`, `WritingCanvas`,
`StudyPlan`, `ComposableArchitecture`).

- [ ] **Step 2: Define the navigation Path enum**

Create `app/Sources/AppFeature/Path.swift`:

```swift
import ComposableArchitecture
import KanjiDetail
import WritingCanvas

/// Destinations reachable from a kanji tap: the study card, then the canvas.
@Reducer
public enum Path {
    case detail(KanjiDetailFeature)
    case writing(KanjiWritingFeature)
}
```

- [ ] **Step 3: Rewire AppFeature (browse stack) to Path**

In `app/Sources/AppFeature/AppFeature.swift`, change the `path` state, action,
push logic, and `forEach` to use `Path`:

```swift
import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import WritingCanvas

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanjiList = KanjiListFeature.State()
        public var path = StackState<Path.State>()
        public init() {}
    }

    // StackActionOf<Path> is not Equatable, so Action intentionally omits Equatable.
    public enum Action {
        case kanjiList(KanjiListFeature.Action)
        case path(StackActionOf<Path>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.kanjiList, action: \.kanjiList) {
            KanjiListFeature()
        }
        Reduce { state, action in
            switch action {
            case let .kanjiList(.kanjiTapped(kanji)):
                state.path.append(.detail(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .path(.element(id: id, action: .detail(.writeTapped))):
                if case let .detail(detail) = state.path[id: id] {
                    state.path.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                }
                return .none
            case .kanjiList, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
```

> Note: `.forEach(\.path, action: \.path)` takes no trailing reducer closure
> because `Path` is a `@Reducer enum` — the macro supplies the per-case reducers.

- [ ] **Step 4: Rewire AppView destination to switch on Path**

In `app/Sources/AppFeature/AppView.swift`, replace the `destination:` closure:

```swift
            } destination: { store in
                switch store.case {
                case let .detail(store):
                    KanjiDetailView(store: store)
                case let .writing(store):
                    KanjiWritingView(store: store)
                }
            }
```
Add `import KanjiDetail` to the file's imports (it already imports `WritingCanvas`).

- [ ] **Step 5: Rewire RootFeature (plan tab stack) to Path**

In `app/Sources/AppFeature/RootFeature.swift`, change `planPath` to use `Path`,
push `.detail` on the plan's `kanjiTapped`, and handle `.detail(.writeTapped)`:

- State: `public var planPath = StackState<Path.State>()`
- Action: `case planPath(StackActionOf<Path>)`
- In the reducer switch, replace the `.plan(.kanjiTapped(kanji))` case body with
  `state.planPath.append(.detail(KanjiDetailFeature.State(kanji: kanji)))`, and
  add:
  ```swift
              case let .planPath(.element(id: id, action: .detail(.writeTapped))):
                  if case let .detail(detail) = state.planPath[id: id] {
                      state.planPath.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                  }
                  return .none
  ```
  and keep `case .browse, .plan, .planPath: return .none`.
- The `.forEach(\.planPath, action: \.planPath)` takes no trailing closure now.
- Add `import KanjiDetail`.

- [ ] **Step 6: Rewire RootView plan destination**

In `app/Sources/AppFeature/RootView.swift`, the plan tab's `NavigationStack`
`destination:` closure switches on `Path`:

```swift
            } destination: { store in
                switch store.case {
                case let .detail(store):
                    KanjiDetailView(store: store)
                case let .writing(store):
                    KanjiWritingView(store: store)
                }
            }
```
Add `import KanjiDetail`.

- [ ] **Step 7: Add a navigation test**

Append to `app/Tests/StudyPlanTests/`? No — put the nav test with AppFeature. Create
`app/Tests/AppFeatureTests/AppFeatureNavTests.swift` and add an `AppFeatureTests`
target. In `app/Project.swift` add:

```swift
        .target(
            name: "AppFeatureTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "com.cobyapp.kanjiwrite.appfeaturetests",
            deploymentTargets: iOS,
            sources: ["Tests/AppFeatureTests/**"],
            dependencies: [.target(name: "AppFeature")]
        ),
```
and add `"AppFeatureTests"` to the scheme `testAction`. The test:

```swift
import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import SharedModels
import WritingCanvas
import XCTest

@testable import AppFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class AppFeatureNavTests: XCTestCase {
    func testTapPushesDetailThenWritePushesWriting() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.kanjiList(.kanjiTapped(.yama)))
        XCTAssertEqual(store.state.path.count, 1)
        XCTAssertEqual(store.state.path.ids.count, 1)
        let id = store.state.path.ids[0]
        guard case .detail = store.state.path[id: id] else {
            return XCTFail("expected a detail destination")
        }

        await store.send(.path(.element(id: id, action: .detail(.writeTapped))))
        XCTAssertEqual(store.state.path.count, 2)
        guard case .writing = store.state.path[id: store.state.path.ids[1]] else {
            return XCTFail("expected a writing destination")
        }
    }
}
```

> `store.exhaustivity = .off` keeps the test focused on the stack transitions
> without asserting every child effect. If the TCA version's StackState test API
> differs (e.g. `ids` access), adjust minimally to assert "1 detail then 2 with a
> writing on top" — that is the behavior under test.

- [ ] **Step 8: Update KanjiApp entry if needed**

`KanjiApp.swift` renders `RootView(store:)` with a `RootFeature.State()` store —
no change needed (the path types changed internally).

- [ ] **Step 9: Generate, build, run the full suite**

Run the test command. Expected: `** TEST SUCCEEDED **` — KanjiDetailFeature,
AppFeatureNav, DictionaryClient (incl. new), and all prior tests pass; the app
builds with tap → study card → write navigation on both tabs.

- [ ] **Step 10: Commit**

```bash
git add app/Project.swift app/Sources/AppFeature/Path.swift app/Sources/AppFeature/AppFeature.swift app/Sources/AppFeature/AppView.swift app/Sources/AppFeature/RootFeature.swift app/Sources/AppFeature/RootView.swift app/Tests/AppFeatureTests/AppFeatureNavTests.swift
git commit -m "feat(app): navigate kanji tap -> study card -> writing canvas (Path enum)"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** re-bundle (spec §3) → Task 1; `WordEntry`/`ExampleSentence`
  + `glosses`/`words`/`sentences` (§4) → Task 2; `KanjiDetailFeature`/`View` (§5)
  → Task 3; `Path` enum nav restructure for both stacks (§6) → Task 4; tests (§7)
  across Tasks 2–4.
- **Existing tests safe:** the enriched DB is a superset, so the prior
  DictionaryClient tests (count 2136, 山 strokes) still pass after re-bundle.
- **Type consistency:** `WordEntry{id,surface,reading,meaningEn}`,
  `ExampleSentence{id,textJa,translations}`, the three client endpoints,
  `KanjiDetailFeature.Action` (`onAppear`/`loaded`/`writeTapped`), and the `Path`
  enum cases (`detail`/`writing`) are used identically across tasks.
- **Manual QA flagged:** study-card layout and the tab navigation feel are
  manual QA; the build + TestStore/integration tests cover the logic and data.
- **Display language:** Korean is fixed for v1 (`glosses["ko"]` headline,
  `translations["ko"]` on sentences); a language selector is a documented
  follow-on.

## Follow-on (not in this slice)

App language selector + i18n; relations (antonym/related) display; Korean word
meanings; stroke-order animation; promote native-gloss hard gate.

# Relations Display in Study Card — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a kanji's antonym/related words in the study card.

**Architecture:** `RelationEntry` in `SharedModels`; a `DictionaryClient.relations` endpoint (GRDB join word_kanji→relation→word); `KanjiDetailFeature` loads relations alongside the other content; `KanjiDetailView` adds a 関連 section.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, TCA 1.26, GRDB. Build/test on iOS 26 iPad sim (UDID from `xcrun simctl list devices available | grep -i ipad`). Run from repo root; `git` from repo root.

Test command shape:
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | tail -12`

---

## Task 1: RelationEntry + DictionaryClient.relations (TDD)

**Files:**
- Modify: `app/Sources/SharedModels/KanjiContent.swift`
- Modify: `app/Sources/DictionaryClient/DictionaryClient.swift`
- Modify: `app/Sources/DictionaryClient/DictionaryClient+Live.swift`
- Modify: `app/Tests/DictionaryClientTests/DictionaryClientTests.swift`

- [ ] **Step 1: Add the model**

Append to `app/Sources/SharedModels/KanjiContent.swift`:

```swift
/// An antonym or related word surfaced for a kanji.
public struct RelationEntry: Equatable, Identifiable, Sendable {
    public var id: String { "\(type):\(surface)" }
    public let surface: String
    public let type: String   // "antonym" | "related"

    public init(surface: String, type: String) {
        self.surface = surface
        self.type = type
    }
}
```

- [ ] **Step 2: Write the failing integration test**

Append to `app/Tests/DictionaryClientTests/DictionaryClientTests.swift` (inside the class):

```swift
    func testLiveReadsRelationsForKanji() async throws {
        let client = DictionaryClient.liveValue
        let allKanji = try await client.allKanji()
        // 大 (big) is common and has antonyms (e.g. 小さい) in JMdict.
        let dai = try XCTUnwrap(allKanji.first { $0.literal == "大" })
        let relations = try await client.relations(dai.id, 20)
        XCTAssertFalse(relations.isEmpty)
        XCTAssertTrue(relations.allSatisfy { $0.type == "antonym" || $0.type == "related" })
        XCTAssertTrue(relations.allSatisfy { !$0.surface.isEmpty })
    }
```

- [ ] **Step 3: Run to verify it fails**

Run the test command. Expected: compile failure — `DictionaryClient` has no `relations`.

- [ ] **Step 4: Add the endpoint to the interface**

In `app/Sources/DictionaryClient/DictionaryClient.swift`, add to the
`@DependencyClient` struct (after `sentences`):

```swift
    public var relations: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [RelationEntry]
```

- [ ] **Step 5: Implement it in the live client**

In `app/Sources/DictionaryClient/DictionaryClient+Live.swift`, add a closure to
the `liveValue` initializer (after `sentences`, with a comma):

```swift
        relations: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [RelationEntry] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT r.type AS type, wb.surface AS surface
                    FROM word_kanji wk
                    JOIN relation r ON r.word_id_a = wk.word_id
                    JOIN word wb ON wb.id = r.word_id_b
                    WHERE wk.kanji_id = ?
                    ORDER BY r.type, wb.surface
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return rows.map { row in
                    RelationEntry(surface: row["surface"], type: row["type"])
                }
            }
        }
```

- [ ] **Step 6: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

> If `大` happens to have no stored relations in this build, switch the test
> kanji to another common one with a JMdict antonym (e.g. `多`, `上`, `行`); the
> assertion is "some common kanji has relations", not a specific count.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/SharedModels/KanjiContent.swift app/Sources/DictionaryClient/DictionaryClient.swift app/Sources/DictionaryClient/DictionaryClient+Live.swift app/Tests/DictionaryClientTests/DictionaryClientTests.swift
git commit -m "feat(app): DictionaryClient.relations endpoint + RelationEntry"
```

---

## Task 2: KanjiDetailFeature loads relations (TDD)

**Files:**
- Modify: `app/Sources/KanjiDetail/KanjiDetailFeature.swift`
- Modify: `app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift`

- [ ] **Step 1: Update the feature test (failing)**

In `app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift`, update
`testOnAppearLoadsContent`: add a `relations` stub to the dependencies and the
4th argument to the expected `.loaded`, plus a relations state assertion.

Add to the `withDependencies` block:
```swift
            $0.dictionaryClient.relations = { _, _ in
                [RelationEntry(surface: "小", type: "antonym")]
            }
```
Change the `.receive(.loaded(...))` to include the 4th arg and assert state:
```swift
        await store.receive(
            .loaded(["ko": "메 산", "en": "mountain"],
                    [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")],
                    [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])],
                    [RelationEntry(surface: "小", type: "antonym")])
        ) {
            $0.isLoading = false
            $0.glosses = ["ko": "메 산", "en": "mountain"]
            $0.words = [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")]
            $0.sentences = [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])]
            $0.relations = [RelationEntry(surface: "小", type: "antonym")]
        }
```

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — `.loaded` takes 3 args / no
`relations` state.

- [ ] **Step 3: Extend the reducer**

In `app/Sources/KanjiDetail/KanjiDetailFeature.swift`:

(a) add to `State`: `public var relations: [RelationEntry] = []`.

(b) change the `loaded` case to carry relations:
```swift
        case loaded([String: String], [WordEntry], [ExampleSentence], [RelationEntry])
```

(c) in `.onAppear`, add a 4th concurrent load and pass it:
```swift
                return .run { send in
                    async let glosses = dictionaryClient.glosses(id)
                    async let words = dictionaryClient.words(id, 12)
                    async let sentences = dictionaryClient.sentences(id, 3)
                    async let relations = dictionaryClient.relations(id, 20)
                    await send(.loaded(
                        (try? await glosses) ?? [:],
                        (try? await words) ?? [],
                        (try? await sentences) ?? [],
                        (try? await relations) ?? []
                    ))
                }
```
(keep the `guard state.glosses.isEmpty` guard at the top of `.onAppear`.)

(d) in the `loaded` case, set the new state:
```swift
            case let .loaded(glosses, words, sentences, relations):
                state.isLoading = false
                state.glosses = glosses
                state.words = IdentifiedArray(uniqueElements: words)
                state.sentences = sentences
                state.relations = relations
                return .none
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/KanjiDetail/KanjiDetailFeature.swift app/Tests/KanjiDetailTests/KanjiDetailFeatureTests.swift
git commit -m "feat(app): KanjiDetailFeature loads word relations"
```

---

## Task 3: 関連 section in the study card view

**Files:**
- Modify: `app/Sources/KanjiDetail/KanjiDetailView.swift`

- [ ] **Step 1: Add the section**

In `app/Sources/KanjiDetail/KanjiDetailView.swift`, add the section to the
`VStack` (after `sentencesSection`):
```swift
                if !store.relations.isEmpty { relationsSection }
```
and add the computed property:
```swift
    private var relationsSection: some View {
        let antonyms = store.relations.filter { $0.type == "antonym" }.map(\.surface)
        let related = store.relations.filter { $0.type == "related" }.map(\.surface)
        return VStack(alignment: .leading, spacing: 8) {
            Text("関連").font(.headline)
            if !antonyms.isEmpty {
                Text("反意").font(.subheadline).foregroundStyle(.secondary)
                Text(antonyms.joined(separator: "、"))
            }
            if !related.isEmpty {
                Text("関連語").font(.subheadline).foregroundStyle(.secondary)
                Text(related.joined(separator: "、"))
            }
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` (build + all tests green).

- [ ] **Step 3: Commit**

```bash
git add app/Sources/KanjiDetail/KanjiDetailView.swift
git commit -m "feat(app): study card 関連 section (antonyms + related words)"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `RelationEntry` + `relations` endpoint (spec §3) → Task 1;
  feature load (§3) → Task 2; 関連 section (§3) → Task 3; tests (§4) across
  Tasks 1–2.
- **Breaking change handled:** `loaded` gains a 4th arg; the only caller
  (`onAppear`) and the only test asserting it are both updated in Task 2.
- **Type consistency:** `RelationEntry{surface,type,id}`, `relations(_:_:)`, and
  the `loaded(_,_,_,_)` arity are used identically across tasks.
- **Robustness:** the integration test's chosen kanji (大) is common with JMdict
  antonyms; a fallback note lists alternates if the build lacks its relations.

## Follow-on

Tap-through to a related word; localized labels; show the bridging word.

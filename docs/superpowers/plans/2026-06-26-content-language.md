# Content Language Selection (i18n part 1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the learner pick the app language (ko/ja/zh/en) and see the study card's meaning + example translations in that language.

**Architecture:** An `AppLanguage` enum in `SharedModels`. Pure fallback helpers (`localizedGloss`/`localizedTranslation`) in `KanjiDetail`. The selection persists via SwiftUI `@AppStorage("appLanguage")` — a language `Menu` in the kanji-list toolbar writes it; `KanjiDetailView` reads it (same key → shared through UserDefaults) and renders meaning/translations accordingly. No reducer/state changes.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, TCA 1.26. Build/test on an iOS 26 iPad simulator (UDID from `xcrun simctl list devices available | grep -i ipad`, e.g. `iPad Pro 11-inch (M5)`). Run from repo root; `git` from repo root.

Test command shape:
`cd app && tuist generate --no-open && xcodebuild test -workspace KanjiWrite.xcworkspace -scheme KanjiWrite -destination 'platform=iOS Simulator,id=<UDID>' 2>&1 | tail -12`

---

## File Structure (this slice)

```
app/
├── Sources/
│   ├── SharedModels/AppLanguage.swift              # AppLanguage enum (new)
│   ├── KanjiDetail/Localization.swift              # localizedGloss/Translation (new)
│   ├── KanjiDetail/KanjiDetailView.swift           # @AppStorage + helpers (modify)
│   └── KanjiListFeature/KanjiListView.swift        # language picker toolbar (modify)
└── Tests/
    └── KanjiDetailTests/LocalizationTests.swift    # AppLanguage + helpers (new)
```

No `Project.swift` changes: `SharedModels` is already a dependency of both
`KanjiDetail` and `KanjiListFeature`.

---

## Task 1: AppLanguage + localization helpers (TDD)

**Files:**
- Create: `app/Sources/SharedModels/AppLanguage.swift`
- Create: `app/Sources/KanjiDetail/Localization.swift`
- Create: `app/Tests/KanjiDetailTests/LocalizationTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `app/Tests/KanjiDetailTests/LocalizationTests.swift`:

```swift
import SharedModels
import XCTest

@testable import KanjiDetail

final class LocalizationTests: XCTestCase {
    func testAppLanguageGlossKeyAndLabel() {
        XCTAssertEqual(AppLanguage.ko.glossKey, "ko")
        XCTAssertEqual(AppLanguage.allCases.map(\.glossKey), ["ko", "ja", "zh", "en"])
        XCTAssertEqual(AppLanguage.ja.label, "日本語")
        XCTAssertEqual(AppLanguage(rawValue: "zh"), .zh)
    }

    func testLocalizedGlossPrefersSelectedThenFallsBack() {
        let glosses = ["ko": "메 산", "ja": "やま。", "zh": "山。", "en": "mountain"]
        XCTAssertEqual(localizedGloss(glosses, .zh), "山。")
        XCTAssertEqual(localizedGloss(glosses, .en), "mountain")
        // missing selected language → en → ja → ko fallback chain
        XCTAssertEqual(localizedGloss(["ja": "やま。", "ko": "메 산"], .zh), "やま。")
        XCTAssertNil(localizedGloss([:], .ko))
    }

    func testLocalizedTranslationFallbackChain() {
        let tr = ["en": "It is high.", "ko": "높다."]
        XCTAssertEqual(localizedTranslation(tr, .ko), "높다.")
        XCTAssertEqual(localizedTranslation(tr, .zh), "It is high.")  // selected absent → en
        XCTAssertNil(localizedTranslation([:], .ja))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the test command. Expected: compile failure — `AppLanguage` / `localizedGloss` not found.

- [ ] **Step 3: Implement AppLanguage**

Create `app/Sources/SharedModels/AppLanguage.swift`:

```swift
/// The app's selected language; drives which gloss/translation is shown.
/// `rawValue` doubles as the `@AppStorage` value and the DB `lang` code.
public enum AppLanguage: String, CaseIterable, Sendable {
    case ko, ja, zh, en

    public var glossKey: String { rawValue }

    public var label: String {
        switch self {
        case .ko: "한국어"
        case .ja: "日本語"
        case .zh: "中文"
        case .en: "English"
        }
    }
}
```

- [ ] **Step 4: Implement the fallback helpers**

Create `app/Sources/KanjiDetail/Localization.swift`:

```swift
import SharedModels

/// The kanji gloss for the selected language, falling back deterministically.
public func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key] { return value }
    }
    return nil
}

/// A sentence translation for the selected language, falling back deterministically.
public func localizedTranslation(_ translations: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ko", "ja", "zh"] {
        if let value = translations[key] { return value }
    }
    return nil
}
```

- [ ] **Step 5: Run to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **` (new LocalizationTests pass).

- [ ] **Step 6: Commit**

```bash
git add app/Sources/SharedModels/AppLanguage.swift app/Sources/KanjiDetail/Localization.swift app/Tests/KanjiDetailTests/LocalizationTests.swift
git commit -m "feat(app): AppLanguage enum + localized gloss/translation helpers (TDD)"
```

---

## Task 2: Study card renders the selected language

**Files:**
- Modify: `app/Sources/KanjiDetail/KanjiDetailView.swift`

- [ ] **Step 1: Read the selected language and use the helpers**

In `app/Sources/KanjiDetail/KanjiDetailView.swift`:

(a) add `import SharedModels` if not already present, and add the stored property
to the view struct (next to `@Bindable var store`):
```swift
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
```

(b) in `header`, change the gloss line from `Text(store.glosses["ko"] ?? "")` to:
```swift
                Text(localizedGloss(store.glosses, appLanguage) ?? "")
                    .font(.title)
```

(c) in `sentencesSection`, change the translation line from
`if let ko = sentence.translations["ko"] { Text(ko)... }` to:
```swift
                    if let translation = localizedTranslation(sentence.translations, appLanguage) {
                        Text(translation).font(.callout).foregroundStyle(.secondary)
                    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` (build + all tests green).

- [ ] **Step 3: Commit**

```bash
git add app/Sources/KanjiDetail/KanjiDetailView.swift
git commit -m "feat(app): study card shows meaning + examples in the selected language"
```

---

## Task 3: Language picker in the kanji-list toolbar

**Files:**
- Modify: `app/Sources/KanjiListFeature/KanjiListView.swift`

- [ ] **Step 1: Add the picker**

In `app/Sources/KanjiListFeature/KanjiListView.swift`:

(a) add `import SharedModels` if not present, and the stored property to the view
struct:
```swift
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
```

(b) add a `.toolbar` modifier to the `Group` (alongside the existing
`.navigationTitle("漢字")` / `.task {...}`):
```swift
        .toolbar {
            Menu {
                Picker("Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
            } label: {
                Image(systemName: "globe")
            }
        }
```

(`AppLanguage` is `String`-backed and `Hashable`/`CaseIterable`, so it works as a
`Picker` selection and `ForEach` id.)

- [ ] **Step 2: Build to verify it compiles**

Run the test command. Expected: `** TEST SUCCEEDED **` — the app builds with the
toolbar language picker; switching it updates the study card (manual QA).

- [ ] **Step 3: Commit**

```bash
git add app/Sources/KanjiListFeature/KanjiListView.swift
git commit -m "feat(app): language picker in kanji-list toolbar (@AppStorage)"
```

---

## Self-Review notes (addressed)

- **Spec coverage:** `AppLanguage` (spec §3) → Task 1; fallback helpers (§3/§5)
  → Task 1; study-card rendering in selected language (§3) → Task 2; picker (§3)
  → Task 3; tests (§5) → Task 1.
- **Refinement vs spec:** uses SwiftUI `@AppStorage("appLanguage")` (shared via
  UserDefaults across the picker and the card) instead of TCA `@Shared`; this
  avoids any reducer/state change and is simpler. The selection is still a single
  app-wide persisted value, as the spec intends.
- **Determinism:** the fallback chains are fixed key orders (no dict-iteration
  nondeterminism); every kanji has all 4 glosses so the headline always resolves.
- **No Project.swift change:** `SharedModels` is already a dep of `KanjiDetail`
  and `KanjiListFeature`.
- **Type consistency:** `AppLanguage` (`glossKey`/`label`/`allCases`),
  `localizedGloss(_:_:)`, `localizedTranslation(_:_:)`, and the
  `@AppStorage("appLanguage")` key are used identically across tasks.
- **Manual QA:** the picker and live switching are manual QA; the helpers and
  build are automated.

## Follow-on (not in this slice)

UI-string localization (String Catalogs for read/usage/examples/tabs/buttons in
4 languages, locale-driven); multilingual word meanings; a settings screen.

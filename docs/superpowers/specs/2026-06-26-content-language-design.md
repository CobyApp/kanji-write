# Content Language Selection (i18n, part 1) — Design

Date: 2026-06-26
Status: Approved (delegated) — ready for implementation planning
Repo: https://github.com/CobyApp/kanji-write
Parent design: `docs/superpowers/specs/2026-06-23-kanji-writing-app-design.md`
Builds on: study-card slice (merged) + the 4-language enriched DB.

## 1. Purpose

The bundled DB already carries glosses and example-sentence translations in
ko/ja/zh/en, but the study card shows Korean only. Let the learner pick the app
language and see the kanji meaning + example translations in that language —
realizing the multilingual core of the original brief.

## 2. Scope & Non-Goals

In scope:
- An `AppLanguage` enum (ko/ja/zh/en) with `glossKey` + display `label`.
- A persisted app-wide selection (`@Shared(.appStorage)`), default Korean.
- A language picker in the kanji-list toolbar.
- The study card renders meaning + sentence translations in the selected
  language (with sensible fallback).

Non-goals (separate follow-on):
- Localizing **UI strings** (section labels 読み/活用/例文, tab names, buttons)
  via String Catalogs across modules — bigger, deferred.
- Multilingual **word** meanings (data only has English word glosses).
- Decoupling UI vs content language (the brief uses one selection).

## 3. Components

- **`AppLanguage`** (in `SharedModels`): `enum AppLanguage: String, CaseIterable,
  Sendable { case ko, ja, zh, en }` with `var glossKey: String { rawValue }`
  (matches the DB `lang` codes) and `var label: String` ("한국어"/"日本語"/"中文"/
  "English"). `rawValue` is the appStorage value.
- **Persistence**: features/views use
  `@Shared(.appStorage("appLanguage")) var appLanguage: AppLanguage = .ko`
  (TCA Sharing). Writing it from the picker persists automatically and updates
  every observer.
- **Picker**: `KanjiListView` gains a toolbar `Menu` (or `Picker`) listing the
  four `AppLanguage` cases, bound to `@Shared appLanguage`. No reducer action —
  the shared value is the single source of truth.
- **Study card**: `KanjiDetailView` reads `@Shared appLanguage` and selects:
  - headline gloss = `glosses[appLanguage.glossKey]`, falling back to
    `glosses["en"]` then `glosses["ja"]` then any;
  - each example's translation = `sentence.translations[appLanguage.glossKey]`,
    falling back to `["en"]` then `["ko"]` then none.
  Readings stay language-neutral. The fallback logic is a small pure helper
  (`localizedGloss`/`localizedTranslation`) that is unit-testable.

## 4. Data flow

Picker writes `@Shared(.appStorage("appLanguage"))` → persisted to UserDefaults
and observed by `KanjiDetailView`, which re-renders meaning/translations from the
already-loaded `glosses`/`sentences` dicts (no new DB query — the detail already
fetches all languages).

## 5. Testing

- **`AppLanguage`**: `glossKey`/`label` for each case; `init(rawValue:)` round-trip.
- **Fallback helpers**: `localizedGloss(glosses, language)` returns the selected
  language when present, else the documented fallback chain; same for
  translations. Pure, unit-tested (in the module that owns them — `KanjiDetail`).
- Build verification: `tuist generate` + `xcodebuild test` green; the picker and
  live language switching are manual QA.

## 6. Build order (this slice)

1. `AppLanguage` enum in `SharedModels` (+ unit test).
2. Fallback helpers (`localizedGloss`/`localizedTranslation`) in `KanjiDetail`
   (TDD), and `KanjiDetailView` uses them with `@Shared appLanguage`.
3. Language picker in `KanjiListView` toolbar bound to `@Shared appLanguage`;
   build green.

## 7. Follow-on (not in this slice)

UI-string localization via String Catalogs (read/usage/examples/tabs/buttons in
4 languages, locale-driven); multilingual word meanings; a dedicated settings
screen.

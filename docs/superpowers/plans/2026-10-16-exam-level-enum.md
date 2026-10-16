# ExamLevel enum migration — Plan

Date: 2026-10-16
Status: Approved (user: proceed; flat `ExamLevel` enum, each exam keeps its own
levels, no value unification).

Design in `docs/superpowers/specs/` lineage: this is a code-level refactor, not a
product change. Levels stay per-exam; only their *representation* changes from
raw `String` to a typed `ExamLevel`.

## Goal

Replace scattered raw level strings ("N5", "10級", …) with a typed `ExamLevel`
enum whose `rawValue` is byte-identical to today's labels, so the bundled
read-only DB, `@AppStorage`, `SectionStat` keys and the widget payload keep
round-tripping with zero data change.

## Non-goals

- Unifying JLPT and 漢検 level *sets* (they stay distinct).
- Any UI/behaviour/feature change. Pure representation refactor.

## The type (`app/Sources/SharedModels/ExamLevel.swift`, new)

```swift
public enum ExamLevel: String, CaseIterable, Sendable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"
    case k10 = "10級", k9 = "9級", k8 = "8級", k7 = "7級", k6 = "6級",
         k5 = "5級", k4 = "4級", k3 = "3級", kPre2 = "準2級", k2 = "2級",
         kPre1 = "準1級", k1 = "1級"
}
```
- `var exam: ExamType` — replaces the fragile `ExamType.of(level:)` prefix sniff.
- `var kankenRank: Int?` / ordering — replaces the two duplicated order arrays.
- DB/storage boundary: bind `.rawValue`, decode `ExamLevel(rawValue:)` (failable,
  tolerate missing/unknown labels on old bundles).

## Micro-tasks (TDD, inner → outer; build/test after each phase)

### Phase 0 — guardrail
- [ ] Keep/My add a test pinning `ExamLevel.allCases.map(\.rawValue)` and the
  per-exam level lists to the exact current label strings. This is the
  serialization contract; if it drifts, progress/stats would be lost.

### Phase 1 — SharedModels core (~25 sites)
- [ ] Add `ExamLevel.swift` + its unit tests (exam mapping, rank, round-trip).
- [ ] `ExamType.levels: [ExamLevel]`, `defaultLevel: ExamLevel`.
- [ ] Fold `kankenRank(_:)`, `passRatio(for:)`, `officialMinutes(for:)`,
  `of(level:)` (KankenQuestion.swift) onto `ExamLevel`.
- [ ] `Kanji.level(for:) -> ExamLevel?`, `belongs(to:exam:)`.
- [ ] `KankenPaper`, `sections(for:)`, `KankenQuestion`/`Yojijukugo`/`TaigiruiPair`/
  `WrongNote`/`SectionStat` level fields.
- [ ] `StudySnapshot.level` stays String at the widget boundary (adapter).

### Phase 2 — DictionaryClient (~20 sites)
- [ ] 11 endpoints take `ExamLevel`; SQL binds `.rawValue`.
- [ ] Generate `kankenRankSQL` CASE from the enum (no hand-kept order).
- [ ] Update `DictionaryClientTests` predicate expectations.

### Phase 3 — consumers (~80 pass-through sites)
- [ ] Review/Curriculum → AppFeature (HomeView/Stats/Onboarding/*Dictionary) →
  TestMode → Worksheet → Practice → KanjiListFeature → Reminders →
  DesignSystem/KanjiDetail. Mostly mechanical.

### Phase 4 — persisted boundaries
- [ ] `@AppStorage("targetLevel")`, `SectionStat.key`, `WrongNote.level`,
  `StudySnapshot`/widget payload read back via `ExamLevel(rawValue:)`; unknown →
  nil/default. Round-trip migration test.

## Verification
- `app/Scripts/generate.sh` then `xcodebuild test` per touched scheme; full
  `fastlane test` at the end. Must be green before claiming done.

## Risks
- rawValue drift → data loss (mitigated by Phase 0 + round-trip tests).
- SQL CASE order drift (mitigated by generating it from the enum).
- Old-bundle missing `jlpt_level` (failable init + existing fallback kept).

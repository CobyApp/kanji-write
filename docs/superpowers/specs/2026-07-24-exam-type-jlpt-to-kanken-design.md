# Exam Type: JLPT → 漢検 — Design (retroactive)

Date: 2026-07-24 (decision), written up 2026-10-16.

Status: Retroactive. This document was reconstructed from the commit history and
the shipped code; no design note was written at the time of the change. It
records *what was decided and why* so the gap between
`2026-07-02-study-plan-and-responsive-design.md` (app is JLPT-only) and
`2026-07-25-kanken-advanced-levels-design.md` (app already has `ExamType.kanken`,
an exam hub, and curated 漢検 question banks) is explained.

Sources of truth for this write-up: `f22e716`, `fdc6d77`, `bbe9402` (2026-07-24,
the transition) and the 2026-07-25 wave (`92871f9`, `8f04169`, `7990969`,
`1fcf639`, …), plus `app/Sources/SharedModels/Kanji.swift` as it stands.

## What actually happened (not a replacement)

The earlier specs describe a **JLPT-only** app: levels N5→N1, a JLPT/grade
classification toggle, JLPT question banks. The 2026-07-25 advanced-levels spec
opens by *assuming* 漢検 already exists — `ExamType.kanken`, levels 10級→2級, an
exam hub with per-paper sections, curated `yojijukugo` / `taigirui`. The
transition between the two was never specced.

It was **not** a pivot that removed JLPT. 漢検 (Kanji Kentei) was introduced as a
**second, co-equal exam** behind a new `ExamType` abstraction; JLPT stayed a
first-class mode. 漢検 then became the product's **lead focus** — the README now
positions the app as "a study app for the 漢検," the dedicated exam hub is 漢検
-shaped, and almost all subsequent content work (四字熟語, 送りがな, 対義語・類義語,
mock papers, 準1級/1級) is 漢検. JLPT received only occasional additions
afterward (`言い換え類義`, `語形成`).

So the accurate framing is **"漢検 added alongside JLPT, then promoted to the
lead exam,"** not "JLPT swapped out for 漢検."

## Why 漢検

- The app's core loop is **handwriting production** (write the kanji from
  meaning/reading, compare to the answer). 漢検's 書き取り / 書字 emphasis fits
  that loop far better than JLPT, which is a reading-only, multiple-choice paper
  with no writing component.
- 漢検 has a **well-defined, examinable curriculum per 級** (10級→1級, with 準2級 /
  準1級) and official paper layouts (大問 order, counts, points, time, pass mark),
  which gives the app a concrete target to reproduce — see
  `kanken-exam-hub.md`.
- It extends the ceiling well past JLPT: 準1級/1級 reach ~6,000 kanji, far beyond
  the ~2,136 jōyō the app started with.

JLPT is retained because the same kanji/word/sentence data serves both, and some
learners orient around JLPT levels.

## The `ExamType` abstraction

The transition is carried entirely by one type, so both exams reuse every
screen, store and question renderer.

```swift
public enum ExamType: String, CaseIterable, Sendable {
    case jlpt
    case kanken

    public var levels: [String] {
        switch self {
        case .jlpt:  ["N5", "N4", "N3", "N2", "N1"]
        case .kanken: ["10級", … , "準2級", "2級", "準1級", "1級"]
        }
    }
    // read from the shared `examType` UserDefaults default
    public static var current: ExamType { … ?? .jlpt }
}
```

Design decisions baked into this:

1. **Levels are plain `String` labels, not an enum**, so a 級 and an N-level flow
   through the same code paths; display and ordering are driven off
   `ExamType.levels`.
2. **One selected exam at a time**, stored in the shared `examType` default and
   resolvable from non-View code via `ExamType.current` — reducers/helpers read
   it without a Binding (`fdc6d77` made ordering exam-type aware; `bbe9402` added
   the Settings toggle + 漢検 level UI).
3. **Per-exam membership on `Kanji`**: `jlptLevel` for JLPT, and for 漢検 the
   normalized `kankenMemberships: [String]` (plus `kankenLevel` as a
   backward-compatible "introduction level"). The 2026-07-25 advanced-levels
   work generalized 漢検 from a single `kanken_level` column to the
   `kanken_membership` join table so a 1/準1級 shared kanji appears in both
   scopes with one review identity.

   ```swift
   public func belongs(to level: String, exam: ExamType) -> Bool {
       switch exam {
       case .jlpt:   jlptLevel == level
       case .kanken: kankenMemberships.contains(level)
       }
   }
   ```
4. **Question routing by label shape**: a level that starts with "N" is JLPT,
   otherwise 漢検 (`KankenQuestion.swift`). JLPT filters stay on `jlpt_level`
   equality; 漢検 filters use `EXISTS` over `kanken_membership`.

## Scope of the change across the app

- **Data pipeline**: add a 漢検 allocation source (`mimneko/kanji-data`, CC0,
  pinned) and tag every kanji with its 級(s). JLPT tagging is unchanged.
- **Classification / browse / plan**: the earlier JLPT/grade toggle is subsumed
  by the exam toggle; level pickers render `ExamType.levels` (`ac94875` reflowed
  the picker to fit 漢検's 10+ levels).
- **Study deck**: 漢検-style question types added; for a while each kanji showed
  **two checks** — JLPT-style and 漢検-style (`92871f9`) — before the dedicated
  hub took over 漢検 practice.
- **Exam hub** (`8f04169`, `7990969`, `1fcf639`): a dedicated 漢検 문제 hub —
  per-section typed practice + mock papers + 오답노트 — that follows the app's
  exam setting and mirrors each level's real 大問 list. Its full evolution lives
  in `docs/kanken-exam-hub.md`.

## Known inconsistency to flag (not resolved here)

The **code default is still `ExamType.current … ?? .jlpt`**, while the product
is now *positioned* as a 漢検 app (README title/subtitle, hub, content weight).
A new user therefore lands in JLPT mode by default despite the 漢検 framing.
This is recorded as a discrepancy, not changed by this retroactive doc — flip
the default to `.kanken` only as a deliberate, tested product decision.

## What this doc deliberately does NOT cover

- The per-級 paper layouts, section catalogs, question generation and
  reliability-first phasing — those are owned by `docs/kanken-exam-hub.md`.
- The 準1級/1級 data model, glyph sourcing and validation — owned by
  `2026-07-25-kanken-advanced-levels-design.md` and
  `docs/kanken-variant-glyphs.md`.

This note only fills the missing "why there are two exams, and why 漢検 leads"
link in the design record.

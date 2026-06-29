# Learning Engine: FSRS Scheduler + Curriculum + Daily Plan — Design

Date: 2026-06-29
Status: Approved (user: FSRS-default; defaults: 7 new/day, level→stroke order,
4-button grading, writing = recall). Research-backed (deep-research report
2026-06-29: FSRS primary, active recall + immediate feedback, handwriting aids
retention, review after some forgetting).

## 1. Purpose

Replace the current Leitner box SRS with a research-grade learning engine so the
app schedules reviews efficiently. The recall event IS writing the kanji from
its meaning/reading with Apple Pencil (active production), with the stroke guide
+ Vision recognition as immediate feedback. The 学習 hub becomes an FSRS-driven
daily session of due reviews + a capped number of new kanji.

## 2. FSRS scheduler (pure, TDD) — `SRS` module

Implement FSRS-4.5 (19 parameters) as pure functions. Default weights:
`[0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621]`

Grades: `Again=1, Hard=2, Good=3, Easy=4`.

- Initial stability: `S0(G) = w[G-1]`.
- Initial difficulty: `D0(G) = w[4] - e^(w[5]·(G-1)) + 1`, clamp [1,10].
- Difficulty update: `ΔD = -w[6]·(G-3)`; `D' = D + ΔD·(10-D)/9`;
  mean-revert `D'' = w[7]·D0(4) + (1-w[7])·D'`; clamp [1,10].
- Retrievability after `t` days: `R(t,S) = (1 + t/(9S))^(-1)`.
- Stability on recall (G≥2):
  `S'r = S·(1 + e^(w[8])·(11-D)·S^(-w[9])·(e^(w[10]·(1-R))-1)·hard·easy)`
  where `hard = w[15] if G=2 else 1`, `easy = w[16] if G=4 else 1`.
- Stability on lapse (G=1): `S'f = w[11]·D^(-w[12])·((S+1)^(w[13])-1)·e^(w[14]·(1-R))`.
- Next interval at desired retention `r`: `I = 9·S·(1/r - 1)`, rounded ≥1 day.
  (At r=0.9, I≈S — a clean test invariant.)

State per card: `stability: Double, difficulty: Double, due: Int (day index),
lastReviewedDay: Int, lapses: Int, reps: Int`. A `MemoryState` value + a pure
`schedule(state:, grade:, today:, retention:) -> MemoryState` function.

Tests (invariants + hand-checked values): S0 equals weights; Good raises
stability/interval, Again resets to S0(1)-scale and increments lapses; lower R
→ larger recall-stability gain; higher retention target → shorter interval;
I≈S at r=0.9; difficulty stays in [1,10].

## 3. Curriculum ordering (pure, TDD)

`studyOrder(_ kanji: [Kanji], classification:) -> [Kanji]`: order by the
classification's level sequence (JLPT N5→N1, or grade 小1→中学; un-leveled last),
then within a level by ascending stroke count (simpler first), then id. This is
the order new kanji are introduced.

## 4. Daily session (pure, TDD) — combines plan + SRS

`todaysSession(records:, order:, today:, newPerDay:) -> Session`:
- `due`: tracked cards with `due <= today`, ordered by due then difficulty.
- `new`: the first `newPerDay` kanji from `studyOrder` that have no record yet.
- A `Session` has `due: [Kanji]` and `new: [Kanji]`.

`newPerDay` default 7, configurable via `@AppStorage("newPerDay")` in 設定.

## 5. Integration

- `ReviewStore` record gains FSRS fields (stability/difficulty/due/lapses/reps),
  migrating from the Leitner box (old records seed S0(Good)). Persisted JSON.
- The 学習 hub (`StudyHubView`) shows the FSRS session: **復習** = `due`,
  **新規** = `new` (capped). Tapping a card → detail → 書いて練習 (recall by
  writing) → on finishing, a 4-button grade (もう一度/むずかしい/できた/かんたん)
  feeds `schedule(...)` and updates the record. The Vision recognition result
  pre-suggests the grade (correct → Good, else Again) but the user confirms.
- The standalone plan (10/14/30-day even distribution) is superseded by the
  FSRS daily flow; the create-plan UI is replaced by "今日のセッション" plus the
  newPerDay setting. (Keep StudyPlan model/scheduler code only if still used;
  otherwise remove.)

## 6. Testing

- FSRS + ordering + session: pure unit tests (TDD), as above.
- Integration: ReviewFeature drives session from records; grading updates the
  record's MemoryState. Existing app tests stay green.
- Visual: simulator screenshots of the hub session + grading.

## 7. Non-goals (follow-on)

Per-user FSRS parameter optimization (ML), radical/primitive build-up ordering
(needs a prerequisite graph), frequency-based ordering (needs a freq field in
the pipeline), vocabulary gating. v1 ships FSRS-default + level/stroke order.

# Promote Native-Gloss to a Hard Gate — Design

Date: 2026-06-26
Status: Approved (delegated) — ready for implementation planning
Builds on: LLM-glosses slice (merged). The real build already has
`kanji_without_native_gloss == 0`.

## 1. Purpose

Lock in the data contract: every shipped kanji must have a Korean (ko) native
gloss. `coverage_report` already tracks `kanji_without_native_gloss`; promote it
from an informational field to a **hard gate** in `assert_core_gates`, mirroring
the existing stroke-order gate.

## 2. Scope

- `assert_core_gates` raises (lists the count) when any kanji lacks a `ko` gloss.
- Update the validator tests: the "passes" tests seed a ko gloss; add a
  "fails when native gloss missing" test. The existing `fails_when_*` tests
  still match their substrings (gate concatenates all problems).
- The real build (`out/kanji.sqlite`) and the `build_db` integration fixture
  (which supplies `llm_glosses_sample.jsonl` → 山/学 get ko) both still pass.

Non-goals: requiring ja/zh (only ko is gated — it is the signature gloss and is
fully populated); changing any other gate.

## 3. Testing

- `assert_core_gates` raises `"missing native"` when a loaded kanji has no ko
  gloss; passes when one is seeded (`load_llm_glosses`).
- Full pipeline suite green; the `build_db` integration test still passes.

## 4. Build order

1. Add the gate check + update validator tests (TDD).

# 부수 레퍼런스 (Radical Reference) — Design

Date: 2026-10-16
Status: Approved (user: "너가 알아서 해줘" — decisions below are mine).

## Intent

A radical (部首) reference the learner can both **browse** (study each radical's
Japanese name + meaning, translated to their language) and **drill into** (tap a
radical to see the kanji written with it, filtered by the active exam/level).
"둘 다" — both uses — was the explicit ask.

## Decisions (mine, since questions were declined)

- **Scope:** all 214 Kangxi radicals (a reference is only useful complete).
- **Data:** the app has radical glyphs (`KangxiRadicals.swift`) and a per-kanji
  radical index (`kanji.radical` 1–214), but no names/meanings. Author a curated
  `sources/radical_reference.jsonl` (Japanese 部首名 in hiragana + a short meaning,
  then ko/zh/en), loaded into a new `radical_reference` table — the same
  curated-then-loaded pattern as `yojijukugo`. A completeness gate requires all
  214 present with every language filled.
- **Location:** a "부수" launcher in Home's 사전(dictionaries) group.
- **Reuse:** `kangxiRadical(number)` for the glyph; `kanji.radical` for membership;
  existing kanji-list row/grid components for the drill-in list.

## Goals
- Browse 214 radicals: glyph, stroke count, 部首名 (ja), meaning in the app language.
- Tap a radical → the kanji that have it, scoped to the active exam + optionally level.
- Fully localized (ko/ja/zh/en) like the rest of the app.

## Non-goals / anti-goals
- Not a radical *decomposition* tool (which radicals make up a kanji) — just the
  Kangxi classifying radical per kanji.
- No new exam question type. This is reference, not a drill.
- Don't invent radical data the gate can't confirm complete.

## Data shape (`radical_reference` table)
`number` (PK, 1–214), `glyph`, `strokes`, `name_ja` (kana), `meaning_ja`,
`meaning_ko`, `meaning_zh`, `meaning_en`. Built from `sources/radical_reference.jsonl`;
reloadable via `refresh_db.py` (repo-owned, like yojijukugo).

## App
- `DictionaryClient.radicals()` → `[RadicalEntry]` (number, glyph, strokes, names,
  meanings, kanji count for the active exam scope).
- `DictionaryClient.kanjiForRadical(number, exam, level?)` → `[Kanji]`.
- A `RadicalReference` feature (list + drill), reached from Home 사전 group,
  localized, following the existing feature-module + TCA conventions.

## Verification
- Pipeline: completeness/format gate test (all 214, 4 languages) + loader test.
- App: `generate.sh` + `xcodebuild test` green for the touched schemes.

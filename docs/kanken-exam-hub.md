# 漢検 문제 허브 (Kanken Exam Hub)

Real-exam-shaped practice for the 漢検, organized by the nine 大問 types of a 2級
paper. Decisions (user-approved 2026-07-25):

- **정확성 우선 (reliability-first).** Ship the types we can generate from real,
  vetted data now; add LLM-curated datasets incrementally.
- **전용 '칸켄 문제' 허브.** A dedicated hub (유형별 연습 + 모의고사 + 오답노트),
  entered from Home. The light per-kanji study check stays as-is.

## The nine 大問 (漢検 2級)

| # | 유형 | 배점 | 데이터 |
|---|------|------|--------|
| 一 | 読み (reading) | 30×1 | ✅ `jlpt_question` kind=reading (1979) |
| 二 | 部首 (radical) | 10×2 | ✅ `kanji.radical` (generated MC) |
| 三 | 熟語の構成 (compound structure) | 10×2 | ⚠️ 否定 auto; rest curated |
| 四 | 四字熟語 (four-char idioms) | 2 | ⚠️ curated dataset (DB has none) |
| 五 | 対義・類義 (antonym/synonym) | 10×2 | ⚠️ curated (392+1646 JMdict only) |
| 六 | 同音・同訓異字 (homophones) | 10×2 | ⚠️ curated context |
| 七 | 誤字訂正 (error correction) | 5×2 | ⚠️ curated |
| 八 | 送りがな (okurigana) | 5×2 | ◐ JMdict verbs/adjectives |
| 九 | 書き取り (writing) | 25×2 | ✅ `jlpt_question` kind=orthography (1036) |

## Per-level exam structure (researched from official sources)

The hub now shows each level's **actual 大問 list** in paper order, so it mirrors a
real 기출 paper. Data-backed sections are playable; the rest are shown for accuracy
and marked 준비 중. Sources: kanken.or.jp (各級の概要), jlpt.jp (大問のねらい PDFs).

### 漢検 (per 級, 10級〜2級 — 準1/1級 use 表外漢字 not yet in the DB)

| 大問 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 準2 | 2 | data |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 読み | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ✅ |
| 筆順 | ● | ● | | | | | | | | | 준비중 |
| 画数 | ● | ● | ● | ● | ● | ● | | | | | ✅ gen |
| 部首 | | | ● | ● | ● | ● | ● | ● | ● | ● | ✅ gen |
| 送りがな | | ● | ● | ● | ● | ● | ● | ● | ● | ● | 준비중 |
| 音読み・訓読み | | | ● | ● | ● | ● | | | | | 준비중 |
| 対義語(・類義語) | | | ● | ● | ● | ● | ● | ● | ● | ● | 준비중 |
| 同音(・同訓)異字 | | | ● | ● | ● | ● | ● | ● | ● | ● | 준비중 |
| 熟語の構成 | | | | | | ● | ● | ● | ● | ● | 준비중 |
| 熟語作り/三字熟語 | | | | ● | ● | | | | | | 준비중 |
| 漢字識別 | | | | | | | ● | ● | | | 준비중 |
| 四字熟語 | | | | | | ● | ● | ● | ● | ● | 준비중 |
| 誤字訂正 | | | | | | | ● | ● | ● | ● | 준비중 |
| 書き取り | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ✅ |

### JLPT 文字・語彙 (per level, 問題1〜)

| 問題 | N5 | N4 | N3 | N2 | N1 | data |
|---|---|---|---|---|---|---|
| 漢字読み | ● | ● | ● | ● | ● | ✅ |
| 表記 | ● | ● | ● | ● | | ✅ |
| 語形成 | | | | ● | | 준비중 |
| 文脈規定 | ● | ● | ● | ● | ● | ✅ |
| 言い換え類義 | ● | ● | ● | ● | ● | 준비중 |
| 用法 | | ● | ● | ● | ● | 준비중 |

## Phasing

- **Phase 1 (this build, reliability-first):** hub scaffold on Home; typed
  practice for 一 読み, 二 部首, 九 書き取り from real data; 오답노트 (wrong-answer
  notebook) with re-solve. Questions scoped to the current 級.
- **Phase 2:** curated datasets → 四字熟語 (+ a 四字熟語 dictionary menu), 対義・類義,
  同音・同訓異字, 誤字訂正, 熟語の構成 labels; 送りがな from JMdict; 모의고사 (full
  mock paper across sections).

## Phase 1 architecture (TestMode module)

- `KankenQuestion` — a ready-to-show MC item (type, prompt, focus, options,
  answer, explanation). Adapted from `JLPTQuestion` or generated (部首).
- `DictionaryClient.kankenQuestions(kankenLevel, kind, limit)` — pull the bank's
  questions for kanji whose `kanken_level` matches, by kind.
- `DictionaryClient.kankenRadicalItems(kankenLevel, limit)` — kanji + radical for
  the 部首 generator (distractors = other real radicals in the pool).
- `WrongNoteStore` — persists missed items (mirror of `QuizStore`); the 오답노트
  screen re-serves them until cleared.
- `KankenExamFeature` / `KankenExamView` — the hub + typed session player,
  reusing the `StudyQuizCard` look.
- Home: a "칸켄 문제" launcher card; a Session case in `RootFeature`.

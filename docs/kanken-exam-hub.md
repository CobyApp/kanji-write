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

### 漢検 (per 級, 10級〜1級 — 準1級/1級 Unicode rows are included)

| 大問 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 準2 | 2 | 準1 | 1 | data |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 読み | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ✅ (〜2級) / 準備中 (準1・1) |
| 筆順 | ● | ● | | | | | | | | | | | 準備中 |
| 画数 | ● | ● | ● | ● | ● | ● | | | | | | | ✅ gen |
| 部首 | | | ● | ● | ● | ● | ● | ● | ● | ● | | | ✅ gen |
| 送りがな | | ● | ● | ● | ● | ● | ● | ● | ● | ● | | | 準備中 |
| 音読み・訓読み | | | ● | ● | ● | ● | | | | | | ● | 準備中 |
| 対義語(・類義語) | | | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | 準備中 |
| 同音(・同訓)異字 | | | ● | ● | ● | ● | ● | ● | ● | ● | | | 準備中 |
| 熟語の構成 | | | | | | ● | ● | ● | ● | ● | | | 準備中 |
| 熟語作り/三字熟語 | | | | ● | ● | | | | | | | | 準備中 |
| 漢字識別 | | | | | | | ● | ● | | | | | 準備中 |
| 四字熟語 | | | | | | ● | ● | ● | ● | ● | ● | ● | 準備中 |
| 誤字訂正 | | | | | | | ● | ● | ● | ● | ● | | 準備中 |
| 書き取り | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ● | ✅ (〜2級) / 準備中 (準1・1) |
| 表外の読み | | | | | | | | | | | ● | | 準備中 |
| 熟語の読み・一字訓読み | | | | | | | | | | | ● | | 準備中 |
| 共通の漢字 | | | | | | | | | | | ● | | 準備中 |
| 語選択 | | | | | | | | | | | | ● | 準備中 |
| 熟字訓・当て字 | | | | | | | | | | | | ● | 準備中 |
| 故事・諺 | | | | | | | | | | | ● | ● | 準備中 |
| 文章題 | | | | | | | | | | | ● | ● | 準備中 |

## Phase 1 데이터셋 측정 결과

2026-07-27에 파이프라인을 처음부터 다시 실행해 번들 데이터베이스를
검증했다.

- 漢検 배정표는 `mimneko/kanji-data` 커밋
  `0be3577f7939ec85d2b4e373a7a94262e7449e13`에 고정했으며, CSV SHA-256은
  `e3a3bade7bb738f6e25d2ff14ea4118ed3b18d9cd32f49dd6a90f5eb6d8ef84f`이다.
- Unihan은 Unicode 17.0.0에 고정했으며, ZIP SHA-256은
  `f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e`이다.
- 전체 학습 한자는 5,936자다. 고급 배정표의 Unicode 행 3,806개를 모두
  수록해 Unicode 커버리지는 3,806/3,806(100%)이며, 이미지 전용 371개는
  검토 대기 상태다.
- `準1級` 멤버십은 1,248개, `1級` 멤버십은 2,955개이며, 두 급에 함께
  속하는 한자는 397개다. 기존 `10級`〜`2級` 증분 수는
  80/160/200/202/193/191/313/284/328/185로 유지됐다.
- 일본어 읽기, 영어 의미, 고급 멤버십 누락은 모두 0개다. 검증된
  stroke path가 있어 쓰기 기능을 제공하는 한자는 5,671개다.
- 검증된 GlyphWiki revision과 SHA-256 manifest 항목이 없는 변형 글자는
  노출하지 않는다. 이번 번들에는 glyph asset과 이미지 변형이 각각 0개다.
- 최종 `kanji.sqlite` SHA-256은
  `8f2ce804d340b698954fec2523725686167d4ca8c2125ae27552dd5aaea4997f`이다.

### 소스 provenance와 고정 정책

`fetch_sources.sh`는 다운로드를 임시 경로에 저장하고 SHA-256이 일치한
경우에만 build input을 교체한다. immutable revision이나 release가 있는
소스는 해당 URL을 사용하며, mutable snapshot만 제공되는 소스는 다운로드
archive와 압축 해제 결과를 모두 고정한다.

- KANJIDIC2와 JMdict는 EDRDG 제공 자료(CC BY-SA 4.0)다. 각각 archive/XML
  SHA-256은
  `25828a7bcd86c6334d29474aad421935d7ff278e1dbcc1c37e3f7e5116727f34`/
  `6123866ad52f8b050e7dcb5d4723f5790db66306c02ad0ad6ac87f4f6030ab58`,
  `74692e3a803d854e632718b28dda601328e0145276861888c4442301a2a7a44a`/
  `b3128bef5795f1baffd46ad24c07b7a6124ca7d47b3105ba104f3e1cafedcba0`다.
- KanjiVG는 release `r20240807`(CC BY-SA 3.0)에 고정했다. archive/XML
  SHA-256은
  `a609387140f2eb42d845e6b10aa361366dda89cf5fba6f06138c4afed0056864`/
  `5353265989dabca7061d5bd6fc51aa9473c2e5f8b6bb9d196b817183c92d96a8`다.
- 漢検 배정표는 `mimneko/kanji-data`의 위 커밋(CC0-1.0)에 고정했다.
- Unihan은 Unicode 17.0.0과 Unicode License v3에 고정했다.
- JLPT mapping 원본은 `davidluzgouveia/kanji-data`의 커밋
  `00fd7079c3890f430759536f91aa5e854ec0ca4f`(MIT)에 고정했다. 원본/생성
  mapping SHA-256은
  `561b72ea9df703c58fae0c68585812e172aaa7611d2fcee6719d55fd2dfd4fa4`/
  `ef8eeccd25b7d2d564ae10c510a94efd5153356e81aa4b9fac4c7091f3733a70`다.
- Tatoeba sentences/links는 CC BY 2.0 FR(일부 sentence는 CC0) 자료다.
  archive/CSV SHA-256은 sentences가
  `771d92ee730d083650f1513ae413b2062d8f4d58ed1f87864bb461d1787e1e3e`/
  `4631dea8a1dddb666081957bf5425d6ded95003d17adda1d475ef41d43973cdd`,
  links가
  `69abec53fe090d0fcd3c20dd0bb441768697668346a66b14bc07d029dc2c88e2`/
  `a3b435a8e168088b103ebc15fe25a209fa35a1560569ac39ad02b438f4980655`다.
- 프로젝트가 관리하는 JSON/JSONL build input도 각각의 SHA-256을
  `fetch_sources.sh`에 고정하며, mismatch가 있으면 build 준비를 중단한다.
  이 파일들은 별도 upstream fetch가 없는 repository-local
  generated/curated 자료이며, 파일별 외부 license metadata는 선언돼 있지
  않다.

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
- `DictionaryClient.examQuestions(level, kind, limit)` — pulls question-bank rows
  for kanji in the requested scope. JLPT uses `jlpt_level` equality; 漢検 uses
  `EXISTS` over normalized `kanken_membership`, so shared `準1級`/`1級` items
  appear in both scopes.
- `DictionaryClient.examRadicalItems(level, limit)` — loads kanji + radical for
  the 部首 generator using the same JLPT-equality/漢検-membership predicate
  (distractors = other real radicals in the pool).
- `WrongNoteStore` — persists missed items (mirror of `QuizStore`); the 오답노트
  screen re-serves them until cleared.
- `KankenExamFeature` / `KankenExamView` — the hub + typed session player,
  reusing the `StudyQuizCard` look.
- Home: a "칸켄 문제" launcher card; a Session case in `RootFeature`.

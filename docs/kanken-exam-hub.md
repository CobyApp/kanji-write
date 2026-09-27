# 漢検 문제 허브 (Kanken Exam Hub)

Real-exam-shaped practice for the 漢検, organized by the nine 大問 types of a 2級
paper. Decisions (user-approved 2026-07-25):

- **정확성 우선 (reliability-first).** Ship the types we can generate from real,
  vetted data now; add LLM-curated datasets incrementally.
- **전용 '칸켄 문제' 허브.** A dedicated hub (유형별 연습 + 모의고사 + 오답노트),
  entered from Home. The light per-kanji study check stays as-is.

## 현재 상태 (2026-09-27) — 실전 형식

- **급수별 대문 구성 = 실제 시험지.** 2026年度第1回 공개 문제(kanken.or.jp 問題例)의
  대문 순서·문항 수·배점을 `app/Sources/SharedModels/KankenPaper.swift`에 옮겼고,
  허브의 유형 목록(`ExamType.kankenSections`)은 이 표에서 만든다. 예: 10급은
  読み・筆順・同じ字の読み・読みを選ぶ・ひらがな一字・反対の意味・書き取り(150점/합격 120/40분),
  6급은 熟語の構成・三字のじゅく語・じゅく語作り 포함 11대문, 1급에는 熟語と一字訓の読み가 있다.
- **실전 모의고사.** 허브 맨 위 카드. 공식 문항 수(10급 81문항〜2급 120문항)와
  배점으로 출제하고, 공식 시간(40/60분)으로 재며, 점수(예: 152/200점)를 공식 합격점과
  비교한다. 실제 시험처럼 풀 때는 정오를 보여 주지 않고 끝나고 한꺼번에 채점하며,
  결과 화면에서 대문별 득점과 틀린 문제(내 답·정답·해설)를 다시 볼 수 있다. 어떤 대문의
  문제가 모자라면 같은 급의 読み/書き取り로 채우고, 합격점은 비율대로 환산한다.
- 기존 모의고사는 **미니 모의고사**(유형당 3/5/10문항, 문항당 30초)로 남겼다.
- **2차 검수.** 작성·파생·漢字識別 문제 5,997개를 전수 검수해 380개 수정·10개 삭제.
  同音・同訓異字 생성기를 다시 짜서(후리가나 정렬로 빈칸 읽기 확인, 상용 읽기만, 실제 단어가
  되는 오답 배제) 2,801문제로 다시 만들었다. 준1급・1급 읽기・쓰기 생성기도 다시 짜서
  (읽기 오답은 대상 한자 부분만 바꾸고, 쓰기 오답은 같은 급의 닮은 한자) 10,042문제로 다시 만들었고,
  단어 문제가 없는 한자는 一字訓読み(1,436)로 채웠다. 호환 코드 포인트를 빼면 준1급 98.6%, 1급 93.3%.
- 새 데이터: 6급 熟語の構成・三字のじゅく語, 5급 熟語作り 각 45문제, 1급 熟語と一字訓の読み 68문제.

## 이전 상태 (2026-09-26)

아래의 준비중 표기와 Phase 계획은 작성 당시 기록이다. 지금은 모든 대문이
플레이 가능하며, 앱에서 準備中 코드도 제거했다.

- **읽기・쓰기 전 급수 커버리지.** 10급〜준2급의 모든 한자에 読み・書き取り 문제가
  1개 이상, 2급은 2개씩 있다(2급은 185자에 読み 34개, 書き取り 26개였다).
  漢検 書き取り는 실제 시험처럼 문장 속 가타카나를 한자로 쓰는 형식이다.
- **답하는 방식.** 허브에서 "직접 쓰기"를 켜면 読み는 히라가나로 입력해 채점하고,
  書き取り・表記는 손으로 쓴 뒤 정답과 비교해 스스로 ○/×를 매긴다.
- **모의고사 채점.** 모의고사는 실제 시험처럼 한 번씩만 풀고(오답 재출제 없음),
  공식 합격 기준(10〜8급 80%, 7급〜준2급 70%, 2급 이상 80%; JLPT는 60% 참고선)
  대비 점수, 대문별 정답 수, 소요 시간, 실제 시험 시간을 보여 준다.
- **熟語の構成**은 현행 5유형(ア〜オ) 5지선다로 다시 작성했다.
- **反対のことば(10・9급)・対義語(8・7급)**는 각 급 배당 한자 안에서 다시 작성했다.
- **同音・同訓異字**는 JMdict 전체 표제어로 검사해 두 번째 정답이 없다.
- **四字熟語・対義語・類義語**는 6급〜1급까지 누적 범위로 출제한다(이전엔 5급〜2급만).
- **音読み・訓読み**는 같은 한자의 다른 읽기를 오답으로 내지 않는다. **筆順**의
  정답은 "3画目" 같은 서수로 표시한다.
- **오답노트**는 틀린 급수별로 저장·표시하며, 저장 경쟁 조건을 없앴다.
- **JLPT**: 言い換え類義는 문장형으로 교체(레벨당 약 55개), 用法 N4〜N1, 文脈規定
  N5/N4, 語形成 N2를 보강했다. 단어 사전은 N 레벨별 공식 어휘 목록(6,129개)을 보여 준다.

- **준1급·1급 읽기·쓰기**: JMdict에 있는 단어만 써서 1,374문제를 새로 작성하고, 사전 단어가
  없는 희귀 한자는 KANJIDIC 훈독으로 一字訓読み 문제(1,488개)를 생성했다. 준1급 97%,
  1급 94%의 한자에 읽기·쓰기 문제가 있다(이전 62%·55%).
- **部首**: 한자 속 모양의 부수(氵, ⻌)를 정답으로, 그 한자의 다른 부분을 오답으로 낸다(KanjiVG).
- **약점 분석·학습 기록**: 유형별 첫 시도 정답률을 저장해 허브 카드와 "약점 집중",
  학습 기록 화면(14일 차트, 예상 정답률, 급수별 진도)에 쓴다.
- **오답노트**: 1·3·7일 간격 복습 후 졸업. 오늘의 복습 퀴즈의 오답도 같은 노트에 쌓인다.
- **모의고사 시간 제한**: 문항당 30초, 시간이 다 되면 자동 제출.

검증 도구: `scripts/check_question_batch.py`(구조), `scripts/check_ambiguity.py`
(복수 정답), `scripts/refresh_db.py`(저장소 관리 테이블을 배포 DB에 재적재).

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

# UI-String Localization (i18n part 2) — Design + Plan

Date: 2026-06-27
Status: Approved (delegated) — combined design + plan (fast path)
Builds on: content-language slice (`@AppStorage("appLanguage")`, `AppLanguage`).

## 1. Purpose

Localize the app's chrome (section labels, tab names, buttons) into ko/ja/zh/en,
driven by the same `appLanguage` selection that already localizes content. The
base development language is Japanese; ko/zh-Hans/en are provided via String
Catalogs.

## 2. Approach

- Add `var localeIdentifier: String` to `AppLanguage` (ko→"ko", ja→"ja",
  zh→"zh-Hans", en→"en").
- At `RootView`, set `.environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))`
  (reading `@AppStorage("appLanguage")`), so all `Text("…")` localize against the
  selected language.
- Add a `Localizable.xcstrings` String Catalog to each module that renders
  user-facing `Text`, with `sourceLanguage = "ja"` and ko/zh-Hans/en
  translations for its strings. Declare the catalog as a target `resources` glob
  in `Project.swift` for each such module.
- `Text("漢字")` etc. stay as-is — the Japanese base string is the catalog key.

Modules needing a catalog + `resources`: `AppFeature`, `KanjiListFeature`,
`KanjiDetail`, `WritingCanvas`, `StudyPlan`, `Review`, `Reminders`.

## 3. String table (ja base → ko / zh-Hans / en)

AppFeature (tabs): 一覧→목록/列表/Browse · プラン→플랜/计划/Plan · 復習→복습/复习/Review · 設定→설정/设置/Settings
KanjiListFeature: 漢字→한자/汉字/Kanji
KanjiDetail: 読み→읽기/读音/Readings · 音→음/音 (keep) · 訓→훈/训 (keep) · 活用→활용 단어/常用词/Words · 例文→예문/例句/Examples · 関連→관련어/相关词/Related · 反意→반의어/反义词/Antonyms · 関連語→관련어/相关词/Related words · 画順→획순/笔顺/Stroke order · 書いて練習→써서 연습/书写练习/Practice writing
WritingCanvas: ガイド表示→가이드 표시/显示笔顺/Show guide · ガイド非表示→가이드 숨김/隐藏笔顺/Hide guide · 消す→지우기/清除/Clear · 保存→저장/保存/Save · 再生→재생/播放/Play
StudyPlan: 学習プランを作成→학습 플랜 만들기/创建学习计划/Create a study plan · プラン作成→플랜 만들기/创建计划/Create plan · 期間→기간/学习期/Duration · 進捗→진도/进度/Progress · 今日の漢字→오늘의 한자/今日的汉字/Today's kanji · プラン→플랜/计划/Plan (nav)
Review: 復習→복습/复习/Review · もう一度→다시/再来/Again · 正解→정답/正确/Correct · 今日の復習はありません→오늘 복습할 한자가 없습니다/今天没有复习/Nothing to review today
Reminders: 設定→설정/设置/Settings · リマインダー→리마인더/提醒/Reminder · 毎日のリマインダー→매일 리마인더/每日提醒/Daily reminder · 時刻→시각/时间/Time · 通知が許可されていません。設定アプリで許可してください。→알림이 허용되지 않았습니다. 설정 앱에서 허용해 주세요./通知未开启，请在系统设置中允许。/Notifications are disabled — enable them in Settings.

(Strings not in the table, e.g. `読み込み失敗`, may also be added; translate
analogously. The `音`/`訓` single-char labels may stay Japanese.)

## 4. Build order

1. Add `localeIdentifier` to `AppLanguage` (+ a unit test in KanjiDetailTests).
2. For each module above: create `Sources/<Module>/Localizable.xcstrings`
   (sourceLanguage ja; ko/zh-Hans/en for that module's strings) and add a
   `resources: ["Sources/<Module>/**"]` entry (or `.../Localizable.xcstrings`)
   to its `Project.swift` target. (DictionaryClient already has resources; it
   has no user-facing Text, so no catalog.)
3. In `RootView`, apply `.environment(\.locale, Locale(identifier:
   appLanguage.localeIdentifier))` using `@AppStorage("appLanguage")`.
4. `tuist generate` + build + run the suite green. Verify a `String(localized:)`
   round-trips one key in a ko locale via a unit test in the module that owns it
   (e.g. assert `String(localized: "消す", bundle: .module, locale: Locale(identifier: "ko"))`
   == "지우기" in WritingCanvasTests) — proves a catalog is wired. Visual QA on
   device for the rest.

## 5. Testing

- `AppLanguage.localeIdentifier` mapping (unit).
- One catalog round-trip per a couple of modules via `String(localized:bundle:locale:)`
  to prove the catalog + resource wiring works (the bulk is manual QA).
- Build green.

## 6. Non-Goals / Follow-on

zh-Hant; right-to-left; per-string review of nuance; pluralization. The `音`/`訓`
mnemonic single-chars and numeric day labels (10日…) stay as-is.

// Exam-hub strings added with the mock-paper scoring, typed / handwritten
// answers and the per-level notebook. Kept apart from UIStrings.swift only
// because that file is already long; access is the same `L.key[language]`.

import Foundation

extension L {
    // Mock paper result
    public static let examScore = L10nText(ko: "점수", ja: "得点", zh: "得分", en: "Score")
    public static let examPassLine = L10nText(ko: "합격선", ja: "合格ライン", zh: "合格线", en: "Pass line")
    public static let examGuideLine = L10nText(
        ko: "목표선(참고)", ja: "目安", zh: "参考线", en: "Suggested target")
    public static let examPassed = L10nText(
        ko: "합격권이에요!", ja: "合格ライン突破！", zh: "达到合格线！", en: "Above the pass line!")
    public static let examNotYet = L10nText(
        ko: "조금만 더! 합격선까지", ja: "合格ラインまであと", zh: "距合格线还差", en: "Almost there — below the pass line by")
    public static let examElapsed = L10nText(ko: "소요 시간", ja: "所要時間", zh: "用时", en: "Time taken")
    public static let examOfficialTime = L10nText(
        ko: "실제 시험", ja: "本番", zh: "正式考试", en: "Real exam")
    public static let examBySection = L10nText(
        ko: "유형별 결과", ja: "大問別の結果", zh: "各题型结果", en: "By section")
    public static let examFirstTry = L10nText(
        ko: "첫 시도 정답률", ja: "一発正解率", zh: "首次正确率", en: "First-try accuracy")
    public static let examMissedCount = L10nText(
        ko: "틀린 문제는 오답노트에 저장했어요", ja: "間違えた問題は間違いノートに保存しました",
        zh: "答错的题已存入错题本", en: "Missed questions were saved to your Mistake notebook")
    public static let examPracticeDone = L10nText(
        ko: "연습 완료!", ja: "練習完了！", zh: "练习完成！", en: "Practice complete!")
    public static let examMockDone = L10nText(
        ko: "모의고사 채점 결과", ja: "模擬試験の採点結果", zh: "模拟考试成绩", en: "Mock exam results")
    public static let points = L10nText(ko: "점", ja: "点", zh: "分", en: " pts")
    public static let minutesUnit = L10nText(ko: "분", ja: "分", zh: "分钟", en: " min")
    public static let loadingQuestions = L10nText(
        ko: "문제를 불러오는 중…", ja: "問題を読み込み中…", zh: "正在加载题目…", en: "Loading questions…")

    // Answer modes
    public static let answerMode = L10nText(ko: "답하는 방법", ja: "解答方法", zh: "作答方式", en: "Answer by")
    public static let answerModeChoice = L10nText(ko: "보기 선택", ja: "選択肢", zh: "选择", en: "Choices")
    public static let answerModeType = L10nText(
        ko: "직접 쓰기", ja: "書いて答える", zh: "自己写", en: "Write it")
    public static let answerModeHint = L10nText(
        ko: "실제 시험처럼 읽기는 히라가나로 입력하고, 쓰기 문제는 손으로 써 봐요.",
        ja: "本番と同じく、読みはひらがなで入力し、書き取りは手で書きます。",
        zh: "像正式考试一样：读音用平假名输入，书写题亲手写。",
        en: "Like the real exam: type readings in hiragana, and write the writing questions by hand.")
    public static let typeReadingPlaceholder = L10nText(
        ko: "히라가나로 읽기를 입력", ja: "読みをひらがなで入力", zh: "用平假名输入读音", en: "Type the reading in hiragana")
    public static let checkAnswer = L10nText(ko: "채점하기", ja: "答え合わせ", zh: "核对答案", en: "Check")
    public static let writeAnswerPrompt = L10nText(
        ko: "밑줄 친 가타카나를 한자로 써 보세요", ja: "カタカナを漢字に直して書きましょう",
        zh: "把片假名改写成汉字", en: "Write the katakana word in kanji")
    public static let revealAnswer = L10nText(ko: "정답 확인", ja: "答えを見る", zh: "看答案", en: "Show answer")
    public static let selfMarkPrompt = L10nText(
        ko: "정답과 같게 썼나요?", ja: "正しく書けましたか？", zh: "写对了吗？", en: "Did you write it correctly?")
    public static let selfMarkRight = L10nText(ko: "맞았어요", ja: "書けた", zh: "写对了", en: "Got it")
    public static let selfMarkWrong = L10nText(ko: "틀렸어요", ja: "書けなかった", zh: "没写对", en: "Missed it")
    public static let clearCanvas = L10nText(ko: "지우기", ja: "消す", zh: "清除", en: "Clear")
    public static let yourAnswer = L10nText(ko: "내 답", ja: "あなたの答え", zh: "你的答案", en: "Your answer")

    // Hub
    public static let examLevelPicker = L10nText(
        ko: "시험 급수", ja: "受験する級", zh: "考试级别", en: "Exam level")
    public static let wrongNoteLevelScope = L10nText(
        ko: "이 급수에서 틀린 문제", ja: "この級で間違えた問題", zh: "本级答错的题", en: "Missed at this level")

    // Generated-question labels (were hard-coded Japanese)
    public static let labelReading = L10nText(ko: "읽기", ja: "読み", zh: "读音", en: "Reading")
    public static let labelMeaning = L10nText(ko: "뜻", ja: "意味", zh: "意思", en: "Meaning")
    public static let labelOn = L10nText(ko: "음독", ja: "音読み", zh: "音读", en: "On'yomi")
    public static let labelKun = L10nText(ko: "훈독", ja: "訓読み", zh: "训读", en: "Kun'yomi")
    public static let labelYojiBlank = L10nText(
        ko: "□에 들어갈 한자", ja: "□に入る漢字", zh: "填入□的汉字", en: "Kanji for the □")
    public static let labelAntonym = L10nText(ko: "반의어", ja: "対義語", zh: "反义词", en: "Antonym")
    public static let labelSynonym = L10nText(ko: "유의어", ja: "類義語", zh: "近义词", en: "Synonym")
    public static let labelOkurigana = L10nText(
        ko: "알맞은 오쿠리가나", ja: "正しい送りがな", zh: "正确的送假名", en: "Correct okurigana")

    /// 筆順's answer is an ordinal ("3画目"), not a stroke count ("3画").
    public static func strokeOrdinal(_ n: Int, _ language: AppLanguage) -> String {
        switch language {
        case .ko: n == 1 ? "첫 번째 획" : "\(n)번째 획"
        case .ja: "\(n)画目"
        case .zh: "第\(n)笔"
        case .en: "Stroke \(n)"
        }
    }

    /// "12:05"-style elapsed time.
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension L {
    public static let weakMix = L10nText(ko: "약점 집중", ja: "苦手克服", zh: "薄弱项突破", en: "Weak spots")
    public static let weakMixSub = L10nText(
        ko: "정답률이 낮은 유형을 섞어서 풀어요", ja: "正答率の低い大問をまとめて練習",
        zh: "混合练习正确率低的题型", en: "A mixed drill of your lowest-scoring sections")
    public static let weakMixEmpty = L10nText(
        ko: "유형별로 몇 문제 풀어 보면 약점을 찾아 드려요", ja: "いくつか解くと苦手な大問が分かります",
        zh: "做几道题后就能找出薄弱题型", en: "Answer a few sections and your weak spots show up here")
    public static let weakMixStart = L10nText(ko: "약점 집중 시작", ja: "苦手克服を始める", zh: "开始练习", en: "Start")
    public static let notTriedYet = L10nText(ko: "시도 전", ja: "未挑戦", zh: "未练习", en: "Not tried")
    public static let wrongDueToday = L10nText(
        ko: "오늘 복습할 문제", ja: "今日の復習対象", zh: "今日待复习", en: "Due today")
    public static let wrongNoteSpaced = L10nText(
        ko: "세 번 연달아 맞히면 노트에서 빠져요 (1·3·7일 간격)",
        ja: "3回続けて正解するとノートから外れます（1・3・7日後）",
        zh: "连续答对三次即从错题本移除（间隔1、3、7天）",
        en: "Leaves the notebook after three clears in a row (1, 3, 7 days apart)")
    public static let timeLimit = L10nText(ko: "제한 시간", ja: "制限時間", zh: "限时", en: "Time limit")
    public static let timeLeft = L10nText(ko: "남은 시간", ja: "残り時間", zh: "剩余时间", en: "Time left")
    public static let timeUp = L10nText(
        ko: "시간 종료 — 풀지 못한 문제는 오답으로 처리했어요",
        ja: "時間切れ — 未解答の問題は不正解になりました",
        zh: "时间到 — 未作答的题按错误计算", en: "Time's up — unanswered questions count as wrong")
    public static let reviewWrongNotes = L10nText(ko: "오답 복습", ja: "間違いノートの復習", zh: "错题复习", en: "Mistake review")
    public static let reviewWrongNotesSub = L10nText(
        ko: "복습할 때가 된 틀린 문제", ja: "復習時期が来た問題",
        zh: "到期该复习的错题", en: "Missed questions that are due again")
}

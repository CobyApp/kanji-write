// Exam-hub strings added with the mock-paper scoring, typed / handwritten
// answers and the per-level notebook. Kept apart from UIStrings.swift only
// because that file is already long; access is the same `L.key[language]`.

import Foundation

extension L {
    // Mock paper result
    public static let examScore = L10nText(ko: "점수", ja: "得点", zh: "得分", en: "Score")
    public static let examPassLine = L10nText(ko: "합격선", ja: "合格ライン", zh: "合格线", en: "Pass line")
    public static let examGuideLine = L10nText(
        ko: "목표선(참고)", ja: "目安", zh: "参考线", en: "Target (guide)")
    public static let examPassed = L10nText(
        ko: "합격권이에요!", ja: "合格ライン突破！", zh: "达到合格线！", en: "Above the pass line!")
    public static let examNotYet = L10nText(
        ko: "조금만 더! 합격선까지", ja: "あと少しで合格ライン", zh: "离合格线还差一点", en: "Almost there — below the pass line by")
    public static let examElapsed = L10nText(ko: "소요 시간", ja: "所要時間", zh: "用时", en: "Time")
    public static let examOfficialTime = L10nText(
        ko: "실제 시험", ja: "本番", zh: "正式考试", en: "Real exam")
    public static let examBySection = L10nText(
        ko: "대문별 결과", ja: "大問別の結果", zh: "各大题结果", en: "By section")
    public static let examFirstTry = L10nText(
        ko: "첫 시도 정답률", ja: "一発正解率", zh: "首次正确率", en: "First-try accuracy")
    public static let examMissedCount = L10nText(
        ko: "틀린 문제는 오답노트에 저장했어요", ja: "間違えた問題は間違いノートに保存しました",
        zh: "答错的题已存入错题本", en: "Missed questions were saved to your notebook")
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
    public static let revealAnswer = L10nText(ko: "정답 확인", ja: "答えを見る", zh: "看答案", en: "Reveal")
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
    public static let labelOn = L10nText(ko: "음독", ja: "音読み", zh: "音读", en: "On reading")
    public static let labelKun = L10nText(ko: "훈독", ja: "訓読み", zh: "训读", en: "Kun reading")
    public static let labelYojiBlank = L10nText(
        ko: "□에 들어갈 한자", ja: "□に入る漢字", zh: "填入□的汉字", en: "Kanji for the □")
    public static let labelAntonym = L10nText(ko: "반대말(対義語)", ja: "対義語", zh: "反义词", en: "Antonym")
    public static let labelSynonym = L10nText(ko: "비슷한 말(類義語)", ja: "類義語", zh: "近义词", en: "Synonym")
    public static let labelOkurigana = L10nText(
        ko: "알맞은 送りがな", ja: "正しい送りがな", zh: "正确的送假名", en: "Correct okurigana")

    /// 筆順's answer is an ordinal ("3画目"), not a stroke count ("3画").
    public static func strokeOrdinal(_ n: Int, _ language: AppLanguage) -> String {
        switch language {
        case .ko: "\(n)번째 획"
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

// Central UI string table. Every interface label is pre-resolved to the selected
// AppLanguage and passed to `Text(_ String)` (which renders verbatim), so in-app
// language switching works reliably across all modules without String Catalogs
// or the process locale. Kanji/word CONTENT (glyphs, readings, glosses) is not
// here — only chrome.

/// A UI label in all four app languages.
public struct L10nText: Sendable, Equatable {
    public let ko: String
    public let ja: String
    public let zh: String
    public let en: String

    public init(ko: String, ja: String, zh: String, en: String) {
        self.ko = ko
        self.ja = ja
        self.zh = zh
        self.en = en
    }

    /// The label for the given app language.
    public subscript(_ language: AppLanguage) -> String {
        switch language {
        case .ko: ko
        case .ja: ja
        case .zh: zh
        case .en: en
        }
    }
}

/// All interface strings. Access as `L.study[appLanguage]`.
public enum L {
    // Navigation / sections
    public static let browse = L10nText(ko: "목록", ja: "一覧", zh: "列表", en: "Browse")
    public static let today = L10nText(ko: "오늘", ja: "今日", zh: "今天", en: "Today")
    public static let strokesUnit = L10nText(ko: "획", ja: "画", zh: "画", en: " strokes")
    public static let dictionary = L10nText(ko: "사전", ja: "辞書", zh: "词典", en: "Dictionary")
    public static let kanjiDictionary = L10nText(ko: "한자사전", ja: "漢字辞書", zh: "汉字词典", en: "Kanji dictionary")
    public static let wordDictionary = L10nText(ko: "단어사전", ja: "単語辞書", zh: "单词词典", en: "Word dictionary")
    public static let expressionDictionary = L10nText(
        ko: "표현사전", ja: "表現辞書", zh: "表达词典", en: "Expression dictionary")
    public static let expressionSearchPrompt = L10nText(
        ko: "표현·읽기·뜻으로 검색", ja: "表現・読み・意味で検索",
        zh: "按表达·读音·意思搜索", en: "Search expressions, readings, meanings")
    public static let expressionSub = L10nText(
        ko: "관용구·표현 검색", ja: "慣用句・表現を検索", zh: "查惯用句·表达", en: "Idioms & phrases")
    public static let wordSearchPrompt = L10nText(
        ko: "단어·읽기·뜻으로 검색", ja: "単語・読み・意味で検索", zh: "按单词·读音·意思搜索",
        en: "Search words, readings, meanings")
    public static let noWordsFound = L10nText(
        ko: "단어를 찾을 수 없어요", ja: "単語が見つかりません", zh: "找不到单词", en: "No words found")
    public static let startStudy = L10nText(ko: "학습 시작", ja: "学習を始める", zh: "开始学习", en: "Start studying")
    // Home groups its launchers so the daily-use ones come first.
    public static let sectionStudy = L10nText(ko: "학습", ja: "学習", zh: "学习", en: "Study")
    public static let sectionTests = L10nText(ko: "테스트", ja: "テスト", zh: "测验", en: "Tests")
    public static let sectionDictionaries = L10nText(ko: "사전", ja: "辞書", zh: "词典", en: "Dictionaries")
    public static let sectionCollection = L10nText(ko: "보관함", ja: "コレクション", zh: "收藏", en: "Collection")
    // Level completion → advance to the next 급수. "{level}" is replaced at display.
    public static let levelCompleteTitle = L10nText(
        ko: "{level} 완료!", ja: "{level} 完了！", zh: "{level} 完成！", en: "{level} complete!")
    public static let goToNextLevel = L10nText(
        ko: "{level} 시작하기", ja: "{level} を始める", zh: "开始 {level}", en: "Start {level}")
    public static let allLevelsComplete = L10nText(
        ko: "모든 급수를 완료했어요! 🎉", ja: "全ての級を制覇しました！🎉",
        zh: "已完成所有级别！🎉", en: "You've finished every level! 🎉")
    public static let startPractice = L10nText(ko: "쓰기 테스트", ja: "書き取りテスト", zh: "书写测验", en: "Writing test")
    public static let close = L10nText(ko: "닫기", ja: "閉じる", zh: "关闭", en: "Close")
    public static let study = L10nText(ko: "학습", ja: "学習", zh: "学习", en: "Study")
    public static let review = L10nText(ko: "복습", ja: "復習", zh: "复习", en: "Review")
    public static let words = L10nText(ko: "단어", ja: "単語", zh: "单词", en: "Words")
    public static let wordbook = L10nText(ko: "단어장", ja: "単語帳", zh: "单词本", en: "Wordbook")
    public static let settings = L10nText(ko: "설정", ja: "設定", zh: "设置", en: "Settings")
    public static let kanji = L10nText(ko: "한자", ja: "漢字", zh: "汉字", en: "Kanji")
    public static let search = L10nText(ko: "검색", ja: "検索", zh: "搜索", en: "Search")
    public static let searchPrompt = L10nText(
        ko: "한자·읽기로 검색", ja: "漢字・読みで検索", zh: "按汉字·读音搜索", en: "Search kanji or reading")

    // Session
    public static let todaySession = L10nText(ko: "오늘의 세션", ja: "今日のセッション", zh: "今日学习", en: "Today")
    public static let todayWords = L10nText(ko: "오늘의 단어", ja: "今日の単語", zh: "今日单词", en: "Today's words")
    public static let newItems = L10nText(ko: "신규", ja: "新規", zh: "新学", en: "New")
    public static let toLearn = L10nText(ko: "오늘 배울 한자", ja: "今日学ぶ漢字", zh: "今天要学的汉字", en: "To learn")
    public static let learn = L10nText(ko: "배우기", ja: "学ぶ", zh: "去学习", en: "Learn")
    public static let learned = L10nText(ko: "습득", ja: "習得", zh: "已掌握", en: "Learned")
    public static let doneToday = L10nText(
        ko: "오늘 학습 완료!", ja: "今日の学習は完了！", zh: "今日学习完成！", en: "All done for today!")
    public static let seeTomorrow = L10nText(ko: "내일 또 만나요", ja: "また明日ね", zh: "明天见", en: "See you tomorrow")

    // Home dashboard + study hub
    public static let greeting = L10nText(ko: "안녕하세요", ja: "こんにちは", zh: "你好", en: "Hello")
    public static let todayProgress = L10nText(ko: "오늘 진도", ja: "今日の進捗", zh: "今日进度", en: "Today")
    public static let continueStudy = L10nText(ko: "이어서 학습", ja: "学習を続ける", zh: "继续学习", en: "Keep going")
    public static let newKanjiSub = L10nText(ko: "새 한자 배우기", ja: "新しい漢字を学ぶ", zh: "学习新汉字", en: "Learn new kanji")
    public static let reviewSub = L10nText(ko: "복습할 시간", ja: "復習の時間", zh: "复习时间", en: "Time to review")
    public static let practiceSub = L10nText(ko: "급수·범위별 한자 쓰기", ja: "レベル・範囲で漢字を書く", zh: "按等级·范围写汉字", en: "Write by level & range")
    public static let allCaughtUp = L10nText(ko: "복습 완료!", ja: "復習は完了！", zh: "复习完成！", en: "All caught up!")

    // Grades (FSRS)
    public static let gradeAgain = L10nText(ko: "다시", ja: "もう一度", zh: "再来", en: "Again")
    public static let gradeHard = L10nText(ko: "어려움", ja: "むずい", zh: "有点难", en: "Hard")
    public static let gradeGood = L10nText(ko: "맞음", ja: "できた", zh: "记住了", en: "Good")
    public static let gradeEasy = L10nText(ko: "쉬움", ja: "かんたん", zh: "很简单", en: "Easy")

    // Detail sections
    public static let readings = L10nText(ko: "읽기", ja: "読み", zh: "读音", en: "Readings")
    public static let onReading = L10nText(ko: "음", ja: "音", zh: "音读", en: "On")
    public static let kunReading = L10nText(ko: "훈", ja: "訓", zh: "训读", en: "Kun")
    public static let strokeOrder = L10nText(ko: "획순", ja: "画順", zh: "笔顺", en: "Stroke order")
    public static let radical = L10nText(ko: "부수", ja: "部首", zh: "部首", en: "Radical")
    public static let examples = L10nText(ko: "예문", ja: "例文", zh: "例句", en: "Examples")
    public static let related = L10nText(ko: "관련", ja: "関連", zh: "相关", en: "Related")
    public static let antonym = L10nText(ko: "반의어", ja: "反意", zh: "反义", en: "Antonym")
    public static let relatedWords = L10nText(ko: "관련어", ja: "関連語", zh: "相关词", en: "Related words")

    // Actions
    public static let practiceWriting = L10nText(ko: "써서 연습", ja: "書いて練習", zh: "手写练习", en: "Practice writing")
    public static let addToReview = L10nText(ko: "복습에 추가", ja: "復習に追加", zh: "加入复习", en: "Add to review")
    public static let addedToReview = L10nText(ko: "복습에 추가됨", ja: "復習に追加済み", zh: "已加入复习", en: "Added to review")
    public static let addToWordbook = L10nText(ko: "단어장에 추가", ja: "単語帳に追加", zh: "加入单词本", en: "Add to wordbook")
    public static let addedToWordbook = L10nText(ko: "단어장에 추가됨", ja: "単語帳に追加済み", zh: "已加入单词本", en: "Added to wordbook")
    public static let grade = L10nText(ko: "채점", ja: "採点", zh: "评分", en: "Grade")
    public static let save = L10nText(ko: "저장", ja: "保存", zh: "保存", en: "Save")
    public static let play = L10nText(ko: "재생", ja: "再生", zh: "播放", en: "Play")
    public static let showGuide = L10nText(ko: "가이드 표시", ja: "ガイド表示", zh: "显示引导", en: "Show guide")
    public static let hideGuide = L10nText(ko: "가이드 숨김", ja: "ガイド非表示", zh: "隐藏引导", en: "Hide guide")
    public static let clear = L10nText(ko: "지우기", ja: "消す", zh: "清除", en: "Clear")

    // Settings
    public static let language = L10nText(ko: "언어", ja: "言語", zh: "语言", en: "Language")
    public static let examType = L10nText(ko: "시험 종류", ja: "試験の種類", zh: "考试类型", en: "Exam")
    public static let reminder = L10nText(ko: "리마인더", ja: "リマインダー", zh: "提醒", en: "Reminder")
    public static let dailyReminder = L10nText(ko: "매일 리마인더", ja: "毎日のリマインダー", zh: "每日提醒", en: "Daily reminder")
    public static let time = L10nText(ko: "시각", ja: "時刻", zh: "时间", en: "Time")
    public static let newPerDay = L10nText(ko: "하루 새 한자", ja: "1日の新しい漢字", zh: "每日新汉字", en: "New kanji / day")
    public static let studyPlan = L10nText(ko: "학습 플랜", ja: "学習プラン", zh: "学习计划", en: "Study plan")
    public static let targetLevel = L10nText(ko: "목표 레벨", ja: "目標レベル", zh: "目标等级", en: "Target level")
    public static let left = L10nText(ko: "남음", ja: "残り", zh: "剩余", en: "left")
    public static let daysUnit = L10nText(ko: "일", ja: "日", zh: "天", en: "d")
    public static let levelDone = L10nText(ko: "이 레벨 완료!", ja: "このレベル完了！", zh: "本等级完成！", en: "Level complete!")
    public static let notifDenied = L10nText(
        ko: "알림이 허용되지 않았습니다. 설정 앱에서 허용해 주세요.",
        ja: "通知が許可されていません。設定アプリで許可してください。",
        zh: "通知未被允许，请在系统设置中开启。",
        en: "Notifications are off. Enable them in the Settings app.")

    // Empty states
    public static let noKanjiFound = L10nText(
        ko: "해당하는 한자가 없어요", ja: "該当する漢字がありません", zh: "没有匹配的汉字", en: "No matching kanji")
    public static let pickKanji = L10nText(
        ko: "한자를 선택하세요", ja: "漢字を選んでください", zh: "请选择一个汉字", en: "Pick a kanji")
    public static let pickKanjiHint = L10nText(
        ko: "목록이나 학습에서 한자를 고르면\n여기에 표시됩니다",
        ja: "一覧や学習から漢字を選ぶと\nここに表示されます",
        zh: "从列表或学习中选择汉字后\n将显示在这里",
        en: "Pick a kanji from Browse or Study\nto see it here")
    public static let wordbookEmpty = L10nText(
        ko: "단어장이 아직 비어 있어요", ja: "単語帳はまだ空です", zh: "单词本还是空的", en: "Your wordbook is empty")
    public static let delete = L10nText(ko: "삭제", ja: "削除", zh: "删除", en: "Delete")
    public static let flashcards = L10nText(ko: "카드 학습", ja: "カード学習", zh: "卡片学习", en: "Flashcards")
    public static let flashcardTapHint = L10nText(
        ko: "카드를 탭하면 뒤집혀요", ja: "カードをタップで裏返し", zh: "点击卡片翻面", en: "Tap the card to flip")
    public static let swipeToDelete = L10nText(
        ko: "밀어서 삭제", ja: "スワイプで削除", zh: "滑动删除", en: "Swipe to delete")
    public static let wordbookEmptyHint = L10nText(
        ko: "단어 상세에서 ‘단어장에 추가’로 저장하면\n여기서 복습할 수 있어요",
        ja: "単語の詳細から「単語帳に追加」で保存すると\nここで復習できます",
        zh: "在单词详情中“加入单词本”保存后\n即可在此复习",
        en: "Save words with “Add to wordbook” in a word’s detail\nto review them here")

    // Study modes (worksheet / practice / test)
    public static let practice = L10nText(ko: "연습", ja: "練習", zh: "练习", en: "Practice")
    public static let test = L10nText(ko: "시험", ja: "テスト", zh: "测验", en: "Test")
    public static let next = L10nText(ko: "다음", ja: "次へ", zh: "下一个", en: "Next")
    public static let prev = L10nText(ko: "이전", ja: "前へ", zh: "上一个", en: "Back")
    public static let done = L10nText(ko: "완료", ja: "完了", zh: "完成", en: "Done")
    public static let showAnswer = L10nText(ko: "정답 보기", ja: "答えを見る", zh: "看答案", en: "Show answer")
    public static let pass = L10nText(ko: "합격", ja: "合格", zh: "通过", en: "Pass")
    public static let fail = L10nText(ko: "불합격", ja: "不合格", zh: "没记住", en: "Fail")
    public static let clearWriting = L10nText(ko: "지우기", ja: "消す", zh: "清除", en: "Clear")
    public static let addCells = L10nText(ko: "칸 10개 추가", ja: "10マス追加", zh: "添加10格", en: "Add 10")

    // Quiz (test what you learned)
    public static let quiz = L10nText(ko: "퀴즈", ja: "クイズ", zh: "测验", en: "Quiz")
    public static let quizSub = L10nText(
        ko: "배운 내용 테스트", ja: "学んだ内容をテスト", zh: "测试所学", en: "Test what you learned")
    public static let quizPrompt = L10nText(
        ko: "정답을 고르세요", ja: "正しい答えを選ぼう", zh: "选择正确答案", en: "Pick the correct answer")
    public static let quizRetry = L10nText(ko: "다시", ja: "再挑戦", zh: "再来", en: "Retry")
    public static let quizKanjiMeaning = L10nText(
        ko: "이 한자의 뜻은?", ja: "この漢字の意味は？", zh: "这个汉字的意思？", en: "Meaning of this kanji?")
    public static let quizWordReading = L10nText(
        ko: "밑줄 친 단어의 읽기는?", ja: "＿＿の読み方は？", zh: "下划线词的读音？", en: "Reading of the underlined word?")
    public static let quizWordMeaning = L10nText(
        ko: "이 단어의 뜻은?", ja: "この単語の意味は？", zh: "这个词的意思？", en: "Meaning of this word?")
    public static let quizKanjiReading = L10nText(
        ko: "이 한자의 음독은?", ja: "この漢字の音読みは？", zh: "这个汉字的音读？", en: "On'yomi of this kanji?")
    public static let quizAntonym = L10nText(
        ko: "반대말을 고르세요", ja: "反対語を選ぼう", zh: "选择反义词", en: "Pick the antonym")
    public static let quizOrthography = L10nText(
        ko: "밑줄 친 말을 한자로?", ja: "＿＿を漢字で書くと？", zh: "下划线词的汉字写法？", en: "Kanji for the underlined word?")
    public static let quizCloze = L10nText(
        ko: "빈칸에 들어갈 말은?", ja: "空欄に入る言葉は？", zh: "选择填入空格的词", en: "Fill in the blank")
    public static let quizFirstTry = L10nText(
        ko: "첫 시도 정답", ja: "一発正解", zh: "首次答对", en: "First-try correct")
    public static let quizCorrect = L10nText(ko: "정답!", ja: "正解！", zh: "答对了！", en: "Correct!")
    public static let quizWrong = L10nText(ko: "오답", ja: "不正解", zh: "答错了", en: "Incorrect")
    public static let quizDone = L10nText(ko: "퀴즈 완료!", ja: "クイズ完了！", zh: "测验完成！", en: "Quiz complete!")
    public static let quizAgain = L10nText(ko: "다시 풀기", ja: "もう一度", zh: "再来一次", en: "Play again")
    // Total number of questions in this quiz session, shown as prefix + count + unit.
    public static let quizTotalPrefix = L10nText(ko: "총 ", ja: "全", zh: "共", en: "")
    public static let quizCountUnit = L10nText(ko: "문제", ja: "問", zh: "题", en: " questions")
    public static let quizNothingDue = L10nText(
        ko: "복습할 내용이 없어요\n학습 후 다시 열어보세요",
        ja: "復習する内容がありません\n学習してからまた開いてね",
        zh: "暂无需要复习的内容\n学习后再来吧", en: "Nothing to review yet\nStudy first, then come back")

    // 칸켄 / JLPT 문제 허브 (exam question hub)
    // Named for what it is: practice organised by the paper's 大問, drawn from
    // the whole selected level. It is not a timed sitting, which is why it
    // belongs under 학습 rather than beside the writing tests.
    public static let kankenHub = L10nText(
        ko: "칸켄 유형별 학습", ja: "漢検 出題形式別の学習",
        zh: "汉检题型学习", en: "Study by Kanken section")
    public static let jlptHub = L10nText(
        ko: "JLPT 유형별 학습", ja: "JLPT 出題形式別の学習",
        zh: "JLPT题型学习", en: "Study by JLPT section")
    public static let kankenContextDesc = L10nText(
        ko: "문맥에 맞는 단어", ja: "文脈に合う語", zh: "符合文意的词", en: "The word that fits the sentence")
    public static let kankenStrokesDesc = L10nText(
        ko: "한자의 총획수", ja: "総画数", zh: "总笔画数", en: "The kanji's stroke count")
    public static let kankenYojiDesc = L10nText(
        ko: "사자성어 읽기·뜻", ja: "四字熟語の読み・意味", zh: "四字成语读音·意思", en: "Four-character idioms")
    public static let kankenOkuriDesc = L10nText(
        ko: "올바른 오쿠리가나 표기", ja: "正しい送りがな", zh: "正确的送假名", en: "The correct okurigana")
    public static let kankenTaigiruiDesc = L10nText(
        ko: "대의어·유의어 고르기", ja: "対義語・類義語", zh: "反义词·近义词", en: "Antonym / synonym")
    public static let kankenOnKunDesc = L10nText(
        ko: "음독·훈독 고르기", ja: "音読み・訓読み", zh: "音读·训读", en: "On / kun reading")
    public static let yojiDictionary = L10nText(
        ko: "사자성어 사전", ja: "四字熟語辞典", zh: "四字成语词典", en: "Idiom dictionary")
    public static let yojiSearchPrompt = L10nText(
        ko: "사자성어·읽기·뜻으로 검색", ja: "四字熟語・読み・意味で検索",
        zh: "按成语·读音·意思搜索", en: "Search idioms, readings, meanings")
    public static let noYojiFound = L10nText(
        ko: "사자성어를 찾을 수 없어요", ja: "四字熟語が見つかりません",
        zh: "找不到四字成语", en: "No idioms found")
    public static let allLevels = L10nText(ko: "전체", ja: "すべて", zh: "全部", en: "All")
    public static let kankenHubSubtitle = L10nText(
        ko: "출제 유형별 연습", ja: "出題形式ごとの練習", zh: "按题型练习", en: "Practice by exam section")
    public static let kankenReadingDesc = L10nText(
        ko: "밑줄 친 한자어의 읽기", ja: "傍線部の読み", zh: "读音", en: "Reading of the underlined word")
    public static let kankenRadicalDesc = L10nText(
        ko: "한자의 부수 고르기", ja: "漢字の部首", zh: "部首", en: "The kanji's radical")
    public static let kankenWritingDesc = L10nText(
        ko: "읽기에 맞는 한자 표기", ja: "正しい漢字表記", zh: "书写", en: "Write it in kanji")
    public static let kankenComingSoon = L10nText(ko: "준비 중", ja: "準備中", zh: "准备中", en: "Coming soon")
    public static let wrongNote = L10nText(ko: "오답노트", ja: "間違いノート", zh: "错题本", en: "Mistake notebook")
    public static let wrongNoteDesc = L10nText(
        ko: "틀린 문제 다시 풀기", ja: "間違えた問題を解き直す", zh: "重做错题", en: "Re-solve missed questions")
    public static let wrongNoteEmpty = L10nText(
        ko: "오답노트가 비어 있어요\n문제를 풀다 틀리면 여기에 모여요",
        ja: "間違いノートは空です\n間違えた問題がここに集まります",
        zh: "错题本是空的\n答错的题会收集到这里", en: "No mistakes yet\nMissed questions collect here")
    public static let wrongNoteCleared = L10nText(
        ko: "오답노트를 모두 풀었어요!", ja: "間違いノートを全部解いたよ！",
        zh: "错题都做完了！", en: "Mistake notebook cleared!")
    public static let backToHub = L10nText(ko: "허브로", ja: "ハブへ", zh: "返回", en: "Back")
    public static let kankenSectionEmpty = L10nText(
        ko: "이 급수에는 아직 문제가 없어요",
        ja: "この級にはまだ問題がありません",
        zh: "该级别暂无题目", en: "No questions for this level yet")
    public static let worksheetWrite = L10nText(ko: "한자를 써보세요", ja: "漢字を書いてみよう", zh: "写一写这个汉字", en: "Write the kanji")
    public static let worksheetVerbs = L10nText(
        ko: "이 한자로 만드는 동사", ja: "この漢字でできる動詞", zh: "用这个汉字构成的动词",
        en: "Verbs with this kanji")
    public static let worksheetOnWords = L10nText(
        ko: "음독으로 읽는 단어", ja: "音読みの単語", zh: "音读的词", en: "On'yomi words")
    public static let worksheetKunWords = L10nText(
        ko: "훈독으로 읽는 단어", ja: "訓読みの単語", zh: "训读的词", en: "Kun'yomi words")
    public static let worksheetOtherWords = L10nText(
        ko: "그 외 단어", ja: "その他の単語", zh: "其他词", en: "Other words")
    public static let worksheetWord = L10nText(ko: "이 한자가 든 단어", ja: "この漢字を使う単語", zh: "含这个汉字的单词", en: "A word using it")
    public static let worksheetExample = L10nText(ko: "예문", ja: "例文", zh: "例句", en: "Example")
    public static let alreadyKnow = L10nText(ko: "이미 알아요", ja: "知ってる", zh: "已会", en: "I know this")
    // Mini quiz mixed into the study deck.
    public static let worksheetQuiz = L10nText(ko: "확인 퀴즈", ja: "確認クイズ", zh: "小测验", en: "Quick check")
    public static let studyQuizMeaning = L10nText(
        ko: "이 한자의 뜻은?", ja: "この漢字の意味は？", zh: "这个汉字的意思是？", en: "What does this kanji mean?")
    public static let studyQuizOn = L10nText(
        ko: "이 한자의 음독은?", ja: "この漢字の音読みは？", zh: "这个汉字的音读？", en: "On'yomi of this kanji?")
    public static let studyQuizKun = L10nText(
        ko: "이 한자의 훈독은?", ja: "この漢字の訓読みは？", zh: "这个汉字的训读？", en: "Kun'yomi of this kanji?")
    public static let studyQuizWordMeaning = L10nText(
        ko: "이 단어의 뜻은?", ja: "この単語の意味は？", zh: "这个词的意思是？", en: "What does this word mean?")
    public static let studyQuizWordReading = L10nText(
        ko: "이 단어의 읽기는?", ja: "この単語の読み方は？", zh: "这个词怎么读？", en: "How is this word read?")
    public static let studyQuizStrokes = L10nText(
        ko: "이 한자는 몇 획?", ja: "この漢字は何画？", zh: "这个汉字几画？", en: "How many strokes?")
    public static let studyQuizRadical = L10nText(
        ko: "이 한자의 부수는?", ja: "この漢字の部首は？", zh: "这个汉字的部首？", en: "What is the radical?")
    public static let testPrompt = L10nText(ko: "뜻을 보고 한자를 써보세요", ja: "意味を見て漢字を書こう", zh: "根据意思写汉字", en: "Write the kanji for this meaning")
    public static let practicePrompt = L10nText(ko: "반복해서 써보며 익히세요", ja: "繰り返し書いて覚えよう", zh: "反复书写来记住", en: "Write it repeatedly to memorize")
    public static let pickToPractice = L10nText(ko: "연습할 한자를 고르세요", ja: "練習する漢字を選ぼう", zh: "选择要练习的汉字", en: "Pick a kanji to practice")
    // 한자쓰기 테스트 (writing test)
    public static let writeTestTitle = L10nText(
        ko: "한자쓰기 테스트", ja: "漢字書き取りテスト", zh: "汉字书写测验", en: "Kanji writing test")
    public static let writeTestStart = L10nText(ko: "테스트 시작", ja: "テスト開始", zh: "开始测验", en: "Start test")
    public static let writeTestPrompt = L10nText(
        ko: "이 뜻의 한자를 써보세요", ja: "この意味の漢字を書こう", zh: "写出这个意思的汉字", en: "Write the kanji for this meaning")
    public static let reading = L10nText(ko: "읽기", ja: "読み", zh: "读音", en: "Reading")
    public static let writeWhat = L10nText(
        ko: "무엇을 쓸까요", ja: "何を書く", zh: "写什么", en: "What to write")
    public static let writeModeKanji = L10nText(ko: "한자", ja: "漢字", zh: "汉字", en: "Kanji")
    public static let writeModeWord = L10nText(ko: "단어", ja: "単語", zh: "单词", en: "Word")
    public static let wordWriteTestTitle = L10nText(
        ko: "단어쓰기 테스트", ja: "単語書きテスト", zh: "单词书写测验", en: "Word writing test")
    public static let wordWriteTestPrompt = L10nText(
        ko: "이 뜻의 단어를 써보세요", ja: "この意味の単語を書こう",
        zh: "写出这个意思的单词", en: "Write the word for this meaning")
    public static let wordWriteSub = L10nText(
        ko: "급수·범위별 단어 쓰기", ja: "級・範囲別の単語書き",
        zh: "按级别范围书写单词", en: "Write words by level and range")
    public static let yojiWriteSub = L10nText(
        ko: "급수별 사자성어 쓰기", ja: "級別の四字熟語書き",
        zh: "按级别书写四字成语", en: "Write idioms by level")
    public static let writeModeYoji = L10nText(
        ko: "사자성어", ja: "四字熟語", zh: "四字成语", en: "Idiom")
    public static let yojiWriteTestTitle = L10nText(
        ko: "사자성어쓰기 테스트", ja: "四字熟語書きテスト",
        zh: "四字成语书写测验", en: "Idiom writing test")
    public static let yojiWriteTestPrompt = L10nText(
        ko: "이 뜻의 사자성어를 써보세요", ja: "この意味の四字熟語を書こう",
        zh: "写出这个意思的四字成语", en: "Write the idiom for this meaning")
    public static let writeLevelYojiTotal = L10nText(
        ko: "이 급수 사자성어", ja: "この級の四字熟語", zh: "本级四字成语",
        en: "Idioms at this level")
    public static let writeRange = L10nText(
        ko: "출제 범위", ja: "出題範囲", zh: "出题范围", en: "Range")
    public static let writeRangeFrom = L10nText(ko: "부터", ja: "から", zh: "从", en: "From")
    public static let writeRangeTo = L10nText(ko: "까지", ja: "まで", zh: "到", en: "To")
    public static let writeLevelKanjiTotal = L10nText(
        ko: "이 급수 한자", ja: "この級の漢字", zh: "本级汉字", en: "Kanji at this level")
    public static let writeLevelWordTotal = L10nText(
        ko: "이 급수 단어", ja: "この級の単語", zh: "本级单词", en: "Words at this level")
    public static let hintShow = L10nText(
        ko: "힌트 보기", ja: "ヒントを見る", zh: "查看提示", en: "Show hint")
    public static let hintHide = L10nText(
        ko: "힌트 숨기기", ja: "ヒントを隠す", zh: "隐藏提示", en: "Hide hint")
    public static let writeStartPos = L10nText(ko: "시작 위치", ja: "開始位置", zh: "起始位置", en: "Start from")
    public static let writeCount = L10nText(ko: "문항 수", ja: "問題数", zh: "题数", en: "Questions")
    public static let writeSeeResult = L10nText(ko: "결과 보기", ja: "結果を見る", zh: "查看结果", en: "See result")
    public static let writeCompareHint = L10nText(
        ko: "실제 한자와 대조해 보세요", ja: "実際の漢字と見比べてね", zh: "和真正的汉字对照一下", en: "Compare with the real kanji")
    public static let writeMine = L10nText(ko: "내 글씨", ja: "自分の字", zh: "我写的", en: "Mine")
    public static let writeAnswer = L10nText(ko: "정답", ja: "正解", zh: "答案", en: "Answer")
    public static let writeRetest = L10nText(ko: "다시 테스트", ja: "もう一度", zh: "再测一次", en: "Test again")
    public static let writeNewRange = L10nText(ko: "범위 다시 선택", ja: "範囲を選び直す", zh: "重新选范围", en: "Pick new range")
    public static let unitCount = L10nText(ko: "자", ja: "字", zh: "字", en: "")
    public static let thisLevelKanji = L10nText(
        ko: "이번 급수 한자", ja: "この級の漢字", zh: "本级汉字", en: "Kanji in this level")
    public static let testChoosePrompt = L10nText(
        ko: "뜻에 맞는 한자를 고르세요", ja: "意味に合う漢字を選ぼう", zh: "选择对应意思的汉字",
        en: "Pick the kanji for this meaning")
    public static let nothingDue = L10nText(ko: "오늘 볼 시험이 없어요", ja: "今日のテストはありません", zh: "今天没有要测验的", en: "Nothing due today")
    public static let noLessons = L10nText(ko: "오늘 배울 한자가 없어요", ja: "今日学ぶ漢字はありません", zh: "今天没有要学的汉字", en: "No new kanji today")

    // Writing
    public static let strokes = L10nText(ko: "획수", ja: "画数", zh: "笔画", en: "Strokes")
    public static let strokeOrderUnavailable = L10nText(
        ko: "획순 데이터가 없어요", ja: "筆順データがありません",
        zh: "暂无笔顺数据", en: "No stroke-order data")
    public static let correct = L10nText(ko: "정답!", ja: "正解！", zh: "正确！", en: "Correct!")
    public static let recognized = L10nText(ko: "인식", ja: "認識", zh: "识别", en: "Recognized")

    // Settings — reset progress
    public static let resetProgress = L10nText(ko: "학습 기록 초기화", ja: "学習記録をリセット", zh: "重置学习记录", en: "Reset progress")
    public static let resetProgressMessage = L10nText(
        ko: "모든 한자·단어 학습 기록과 단어장이 삭제됩니다. 되돌릴 수 없어요.",
        ja: "すべての漢字・単語の学習記録と単語帳が削除されます。元に戻せません。",
        zh: "将删除所有汉字·单词的学习记录和单词本，无法撤销。",
        en: "Deletes all kanji/word progress and your wordbook. This can’t be undone.")
    public static let cancel = L10nText(ko: "취소", ja: "キャンセル", zh: "取消", en: "Cancel")
    // Study-done gate: shown when today's goal is met and 학습하기 is tapped again.
    public static let studyDoneTitle = L10nText(
        ko: "오늘 학습 완료!", ja: "今日の学習が完了！", zh: "今日学习完成！", en: "Today's study is done!")
    public static let studyDoneMessage = L10nText(
        ko: "내일 학습을 미리 당겨서 할까요?",
        ja: "明日の学習を先取りしますか？",
        zh: "要提前学习明天的内容吗？",
        en: "Pull tomorrow's study forward and do it now?")
    public static let studyPullTomorrow = L10nText(
        ko: "내일 학습 미리 하기", ja: "明日の学習を先取り", zh: "提前学明天的", en: "Study tomorrow's now")
    public static let studyQuizPending = L10nText(
        ko: "오늘 퀴즈를 아직 안 풀었어요.",
        ja: "今日のクイズをまだ解いていません。",
        zh: "今天的测验还没做。",
        en: "You haven't taken today's quiz yet.")
    public static let studyTakeQuizNow = L10nText(
        ko: "오늘 퀴즈 풀기", ja: "今日のクイズを解く", zh: "做今天的测验", en: "Take today's quiz")
    public static let reset = L10nText(ko: "초기화", ja: "リセット", zh: "重置", en: "Reset")

    // Practice — level filter
    public static let level = L10nText(ko: "급수", ja: "レベル", zh: "级别", en: "Level")

    // Home plan (level + date range → per-day goal)
    public static let planStart = L10nText(ko: "시작일", ja: "開始日", zh: "开始日期", en: "Start")
    public static let planEnd = L10nText(ko: "목표일", ja: "目標日", zh: "目标日期", en: "Goal")
    public static let perDayGoal = L10nText(ko: "하루 목표", ja: "1日の目標", zh: "每日目标", en: "Daily goal")
    public static let perDayUnit = L10nText(ko: "자", ja: "字", zh: "字", en: "/day")
    // Plan mode: set by goal date, or by fixed daily count.
    public static let planByDate = L10nText(ko: "목표일", ja: "目標日", zh: "目标日", en: "By date")
    public static let planByCount = L10nText(ko: "하루 개수", ja: "1日の数", zh: "每日数", en: "By count")
    public static let finishBy = L10nText(ko: "완료 예정", ja: "完了予定", zh: "预计完成", en: "Finish by")

    // Streak + today's goal
    public static let streak = L10nText(ko: "연속", ja: "連続", zh: "连续", en: "Streak")
    public static let streakUnit = L10nText(ko: "일째", ja: "日", zh: "天", en: "days")
    public static let todayGoal = L10nText(ko: "오늘 목표", ja: "今日の目標", zh: "今日目标", en: "Today")

    // Bookmarks
    public static let bookmark = L10nText(ko: "북마크", ja: "ブックマーク", zh: "收藏", en: "Bookmark")
    public static let bookmarks = L10nText(ko: "북마크", ja: "ブックマーク", zh: "收藏", en: "Bookmarks")
    public static let noBookmarkedKanji = L10nText(
        ko: "북마크한 한자가 없어요", ja: "ブックマークした漢字はありません",
        zh: "还没有收藏的汉字", en: "No bookmarked kanji yet")
    public static let noBookmarkedWords = L10nText(
        ko: "저장한 단어가 없어요", ja: "保存した単語はありません",
        zh: "还没有保存的单词", en: "No saved words yet")

    // Notification
    public static let notifTitle = L10nText(ko: "한자 연습", ja: "漢字の練習", zh: "汉字练习", en: "Kanji practice")
    public static let notifBody = L10nText(
        ko: "오늘의 한자를 써서 외워봐요.",
        ja: "今日の漢字を書いて覚えましょう。",
        zh: "写一写今天的汉字来记住它们吧。",
        en: "Write today’s kanji to make them stick.")
}

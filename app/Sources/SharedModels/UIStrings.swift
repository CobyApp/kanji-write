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
    public static let reminder = L10nText(ko: "리마인더", ja: "リマインダー", zh: "提醒", en: "Reminder")
    public static let dailyReminder = L10nText(ko: "매일 리마인더", ja: "毎日のリマインダー", zh: "每日提醒", en: "Daily reminder")
    public static let time = L10nText(ko: "시각", ja: "時刻", zh: "时间", en: "Time")
    public static let newPerDay = L10nText(ko: "하루 새 한자", ja: "1日の新しい漢字", zh: "每日新汉字", en: "New kanji / day")
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
    public static let wordbookEmptyHint = L10nText(
        ko: "단어 상세에서 ‘단어장에 추가’로 저장하면\n여기서 복습할 수 있어요",
        ja: "単語の詳細から「単語帳に追加」で保存すると\nここで復習できます",
        zh: "在单词详情中“加入单词本”保存后\n即可在此复习",
        en: "Save words with “Add to wordbook” in a word’s detail\nto review them here")

    // Writing
    public static let strokes = L10nText(ko: "획수", ja: "画数", zh: "笔画", en: "Strokes")
    public static let correct = L10nText(ko: "정답!", ja: "正解！", zh: "正确！", en: "Correct!")
    public static let recognized = L10nText(ko: "인식", ja: "認識", zh: "识别", en: "Recognized")

    // Notification
    public static let notifTitle = L10nText(ko: "한자 연습", ja: "漢字の練習", zh: "汉字练习", en: "Kanji practice")
    public static let notifBody = L10nText(
        ko: "오늘의 한자를 써서 외워봐요.",
        ja: "今日の漢字を書いて覚えましょう。",
        zh: "写一写今天的汉字来记住它们吧。",
        en: "Write today’s kanji to make them stick.")
}

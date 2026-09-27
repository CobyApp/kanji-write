import SharedModels

extension ExamSection {
    /// The 大問's name in the learner's language, shown under the Japanese
    /// title the paper prints — 読み means nothing to someone who can't read it
    /// yet. nil in Japanese, where the printed title is already the name.
    public func localizedName(_ language: AppLanguage) -> String? {
        guard language != .ja, let names = Self.names[id] else { return nil }
        return names[language]
    }

    private static let names: [String: L10nText] = [
        "reading": L10nText(ko: "읽기", ja: "読み", zh: "读音", en: "Reading"),
        "writing": L10nText(ko: "쓰기", ja: "書き取り", zh: "书写", en: "Writing"),
        "orthography": L10nText(ko: "표기", ja: "表記", zh: "表记", en: "Spelling in kanji"),
        "context": L10nText(ko: "문맥에 맞는 말", ja: "文脈規定", zh: "语境选词", en: "Word in context"),
        "iikae": L10nText(ko: "바꿔 말하기", ja: "言い換え類義", zh: "近义替换", en: "Paraphrase"),
        "youhou": L10nText(ko: "용법", ja: "用法", zh: "用法", en: "Usage"),
        "gokeisei": L10nText(ko: "어형성", ja: "語形成", zh: "构词", en: "Word formation"),
        "radical": L10nText(ko: "부수", ja: "部首", zh: "部首", en: "Radical"),
        "strokes": L10nText(ko: "획수", ja: "画数", zh: "笔画数", en: "Stroke count"),
        "hitsujun": L10nText(ko: "획순", ja: "筆順", zh: "笔顺", en: "Stroke order"),
        "yoji": L10nText(ko: "사자성어", ja: "四字熟語", zh: "四字成语", en: "Four-character idioms"),
        "okuri": L10nText(ko: "오쿠리가나", ja: "送りがな", zh: "送假名", en: "Okurigana"),
        "taigirui": L10nText(ko: "반의어·유의어", ja: "対義語・類義語", zh: "反义词·近义词", en: "Antonyms & synonyms"),
        "hantai": L10nText(ko: "반대말", ja: "反対のことば", zh: "反义词", en: "Opposites"),
        "taigi": L10nText(ko: "반의어", ja: "対義語", zh: "反义词", en: "Antonyms"),
        "onkun": L10nText(ko: "음독·훈독", ja: "音読み・訓読み", zh: "音读·训读", en: "On'yomi & kun'yomi"),
        "doonkun": L10nText(ko: "동음·동훈 이자", ja: "同音・同訓異字", zh: "同音·同训异字", en: "Homophone kanji"),
        "shikibetsu": L10nText(ko: "한자 식별", ja: "漢字識別", zh: "汉字识别", en: "Kanji identification"),
        "sanji": L10nText(ko: "세 글자 숙어", ja: "三字熟語", zh: "三字词", en: "Three-kanji words"),
        "tsukuri": L10nText(ko: "숙어 만들기", ja: "熟語作り", zh: "组词", en: "Build the compound"),
        "kousei": L10nText(ko: "숙어의 구성", ja: "熟語の構成", zh: "词语结构", en: "Compound structure"),
        "goji": L10nText(ko: "오자 정정", ja: "誤字訂正", zh: "改错字", en: "Wrong-kanji correction"),
        "common-kanji": L10nText(ko: "공통 한자", ja: "共通の漢字", zh: "共同汉字", en: "Shared kanji"),
        "hyogai-reading": L10nText(ko: "표외 읽기", ja: "表外の読み", zh: "表外读音", en: "Non-standard readings"),
        "jukugo-reading": L10nText(ko: "숙어 읽기·한 글자 훈독", ja: "熟語の読み・一字訓読み", zh: "词语读音·单字训读", en: "Compound & single-kanji readings"),
        "word-selection": L10nText(ko: "어휘 선택", ja: "語選択", zh: "选词", en: "Word choice"),
        "jukujikun-ateji": L10nText(ko: "숙자훈·아테지", ja: "熟字訓・当て字", zh: "熟字训·借字", en: "Special readings"),
        "koji-kotowaza": L10nText(ko: "고사·속담", ja: "故事・諺", zh: "典故·谚语", en: "Sayings & proverbs"),
        "passage": L10nText(ko: "문장 문제", ja: "文章題", zh: "文章题", en: "Passage"),
    ]
}

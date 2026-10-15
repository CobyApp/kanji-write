import SharedModels

extension ExamSection {
    /// What the section asks, in the learner's language. Keyed by the section
    /// rather than its render type: ten 大問 share `.writing` and would
    /// otherwise all tell the reader to write a reading in kanji.
    public func instruction(_ language: AppLanguage) -> String {
        switch id {
        case "kousei": return L.kankenKouseiDesc[language]
        case "goji": return L.kankenGojiDesc[language]
        case "shikibetsu": return L.kankenShikibetsuDesc[language]
        case "common-kanji": return L.kankenKyotsuDesc[language]
        case "sanji": return L.kankenSanjiDesc[language]
        case "doonkun": return L.kankenDoonDesc[language]
        case "tsukuri": return L.kankenTsukuriDesc[language]
        case "word-selection": return L.kankenGoselectDesc[language]
        case "koji-kotowaza": return L.kankenKotowazaDesc[language]
        case "hyogai-reading": return L.kankenHyogaiDesc[language]
        case "jukujikun-ateji": return L.kankenJukujikunDesc[language]
        case "gokeisei": return L.kankenGokeiseiDesc[language]
        case "iikae": return L.kankenIikaeDesc[language]
        case "youhou": return L.kankenYouhouDesc[language]
        case "passage": return L.kankenPassageDesc[language]
        case "jukugo-reading": return L.kankenJukugoKunDesc[language]
        case "hantai", "taigi": return L.kankenHantaiDesc[language]
        default: return renderType.instruction(language)
        }
    }
}

extension ExamSection {
    /// The 大問 directive as the real paper prints it — in Japanese, regardless
    /// of the learner's language — so a sitting reads like the actual exam. The
    /// learner-language `instruction` is shown underneath as a gloss.
    public static func japaneseDirective(for id: String?, type: KankenQuestionType) -> String {
        switch id {
        case "reading": return "次の──線の漢字の読みをひらがなで記せ。"
        case "writing", "orthography": return "次の──線のカタカナを漢字に直せ。"
        case "doonkun": return "次の──線のカタカナにあてはまる漢字を記せ。"
        case "shikibetsu": return "三つの□に共通する漢字を入れて熟語を作れ。"
        case "sanji": return "空欄にあてはまる漢字を記し、三字熟語を完成させよ。"
        case "common-kanji": return "二つの熟語に共通してあてはまる漢字を記せ。"
        case "kousei": return "次の熟語は下のどの組み合わせにあたるか、記号で答えよ。"
        case "goji": return "まちがって使われている漢字を正しい漢字に直せ。"
        case "tsukuri": return "次の意味にあてはまる熟語を選べ。"
        case "taigirui": return "次の語の対義語・類義語を漢字で記せ。"
        case "hantai": return "次の語と反対の意味のことばを記せ。"
        case "taigi": return "次の語の対義語を記せ。"
        case "okuri": return "次の──線のカタカナを漢字一字と送りがな(ひらがな)に直せ。"
        case "onkun": return "次の──線の漢字の読みを記せ。"
        case "hitsujun": return "太い画のところは筆順の何画目か、算用数字で答えよ。"
        case "strokes": return "次の漢字の総画数を算用数字で答えよ。"
        case "radical": return "次の漢字の部首を記せ。"
        case "yoji": return "四字熟語について、空欄の漢字または意味を答えよ。"
        case "hyogai-reading": return "次の──線の漢字の読み(表外の読み)をひらがなで記せ。"
        case "jukugo-reading": return "次の──線の漢字の訓読みをひらがなで記せ。"
        case "jukujikun-ateji": return "次の──線の熟字訓・当て字の読みをひらがなで記せ。"
        case "word-selection": return "次の意味にあてはまる語を選び、漢字で記せ。"
        case "koji-kotowaza": return "次の──線のカタカナを漢字に直せ。"
        case "passage": return "文章中の──線の漢字の読み・カタカナを答えよ。"
        // JLPT 文字・語彙
        case "context", "gokeisei": return "(　)に入れるのに最もよいものを一つ選べ。"
        case "iikae": return "──の言葉に意味が最も近いものを一つ選べ。"
        case "youhou": return "次の言葉の使い方として最もよいものを一つ選べ。"
        default:
            switch type {
            case .reading: return "次の──線の漢字の読みをひらがなで記せ。"
            case .writing: return "次の──線のカタカナを漢字に直せ。"
            case .radical: return "次の漢字の部首を記せ。"
            case .strokes: return "次の漢字の総画数を算用数字で答えよ。"
            case .hitsujun: return "太い画のところは筆順の何画目か答えよ。"
            case .yojijukugo: return "四字熟語を完成させよ。"
            case .okurigana: return "次の──線のカタカナを漢字と送りがなに直せ。"
            case .taigirui: return "次の語の対義語・類義語を漢字で記せ。"
            case .onkun: return "次の──線の漢字の読みを記せ。"
            case .context: return "(　)に入れるのに最もよいものを一つ選べ。"
            }
        }
    }
}

extension KankenQuestionType {
    /// The generic instruction for a render type, used when a section has no
    /// wording of its own.
    public func instruction(_ language: AppLanguage) -> String {
        switch self {
        case .reading: L.kankenReadingDesc[language]
        case .radical: L.kankenRadicalDesc[language]
        case .writing: L.kankenWritingDesc[language]
        case .context: L.kankenContextDesc[language]
        case .strokes: L.kankenStrokesDesc[language]
        case .yojijukugo: L.kankenYojiDesc[language]
        case .okurigana: L.kankenOkuriDesc[language]
        case .taigirui: L.kankenTaigiruiDesc[language]
        case .onkun: L.kankenOnKunDesc[language]
        case .hitsujun: L.kankenHitsujunDesc[language]
        }
    }
}

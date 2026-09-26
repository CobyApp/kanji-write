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

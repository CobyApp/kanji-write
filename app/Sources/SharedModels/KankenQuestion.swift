import Foundation

/// How a question renders / is generated in the player. Sections whose type is
/// `.comingSoon` are shown for structural accuracy (they exist on the real paper)
/// but aren't yet backed by data, so they aren't playable.
public enum KankenQuestionType: String, CaseIterable, Sendable, Equatable, Codable {
    case reading          // 読み / 漢字読み — sentence, answer is a reading
    case radical          // 部首 — kanji glyph, options are 部首 glyphs
    case writing          // 書き取り / 表記 — sentence, answer is a kanji spelling
    case context          // 文脈規定 — sentence cloze
    case strokes          // 画数 — kanji glyph, answer is the stroke count
    case yojijukugo       // 四字熟語 — idiom glyph, answer is its reading / meaning
    case okurigana        // 送りがな — カナ word, answer is the kanji+okurigana form
    case taigirui         // 対義語・類義語 — a word, answer is its antonym / synonym
    case onkun            // 音読み・訓読み — kanji glyph, answer is an on / kun reading
    case hitsujun         // 筆順 — the glyph with one stroke marked, answer is its ordinal
    case comingSoon       // real 大問, curated data not ready yet (not playable)

    /// Reading answers get slightly larger option type than kanji/word answers.
    public var isReading: Bool { self == .reading }
    /// Renders as a centered glyph (kanji / idiom) rather than a sentence.
    public var isGlyphPrompt: Bool { self == .radical || self == .strokes || self == .yojijukugo }
}

/// A 四字熟語 (four-character idiom): the idiom, its full kana reading, meanings,
/// and the 漢検 級 it's classified under. Powers the 四字熟語 exam section and the
/// 사자성어 dictionary.
public struct Yojijukugo: Equatable, Identifiable, Sendable {
    public let id: Int
    public let yoji: String
    public let reading: String
    public let meaningJa: String?
    public let meaningKo: String?
    public let level: String

    public init(id: Int, yoji: String, reading: String,
                meaningJa: String?, meaningKo: String?, level: String) {
        self.id = id
        self.yoji = yoji
        self.reading = reading
        self.meaningJa = meaningJa
        self.meaningKo = meaningKo
        self.level = level
    }

    /// The meaning in the app language, falling back Japanese → Korean.
    public func meaning(_ language: AppLanguage) -> String? {
        switch language {
        case .ko: meaningKo ?? meaningJa
        case .ja: meaningJa ?? meaningKo
        default: meaningJa ?? meaningKo
        }
    }
}

/// A 対義語・類義語 pair: a prompt word and its antonym ("対義") or synonym ("類義"),
/// with readings and the 漢検 級. Powers the 対義語・類義語 exam section.
public struct TaigiruiPair: Equatable, Identifiable, Sendable {
    public let id: Int
    public let word: String
    public let wordReading: String
    public let answer: String
    public let answerReading: String
    public let relation: String   // "対義" | "類義"
    public let level: String

    public init(id: Int, word: String, wordReading: String, answer: String,
                answerReading: String, relation: String, level: String) {
        self.id = id
        self.word = word
        self.wordReading = wordReading
        self.answer = answer
        self.answerReading = answerReading
        self.relation = relation
        self.level = level
    }
}

/// A kanji with its 音読み / 訓読み reading sets — the input to the 音読み・訓読み
/// question generator (on = katakana, kun = hiragana, okurigana dots stripped).
public struct OnKunItem: Equatable, Sendable {
    public let kanjiID: Int
    public let literal: String
    public let onReadings: [String]
    public let kunReadings: [String]
    public init(kanjiID: Int, literal: String, onReadings: [String], kunReadings: [String]) {
        self.kanjiID = kanjiID
        self.literal = literal
        self.onReadings = onReadings
        self.kunReadings = kunReadings
    }
}

/// A raw kanji + its stroke count, the input to the 画数 question generator.
public struct StrokeItem: Equatable, Sendable {
    public let kanjiID: Int
    public let literal: String
    public let strokeCount: Int
    public init(kanjiID: Int, literal: String, strokeCount: Int) {
        self.kanjiID = kanjiID
        self.literal = literal
        self.strokeCount = strokeCount
    }
}

/// One 大問 (question section) of an exam paper at a given level — its label, the
/// 大問 marker, how its questions render/generate, its bank `kind`, and whether it
/// is playable yet. The section list is level-specific (see `ExamType.sections`),
/// mirroring the real per-level paper structure.
public struct ExamSection: Equatable, Sendable, Identifiable {
    public let id: String            // stable per section, unique within a level
    public var numeral: String       // 大問 marker ("一" / "1" …), assigned by order
    public let jaTitle: String       // section name as printed on the exam
    public let renderType: KankenQuestionType
    public let kind: String?         // bank kind to query; nil = generated / n/a
    public let available: Bool       // playable now (data-backed) vs. 준비 중

    public init(id: String, numeral: String, jaTitle: String,
                renderType: KankenQuestionType, kind: String?, available: Bool) {
        self.id = id
        self.numeral = numeral
        self.jaTitle = jaTitle
        self.renderType = renderType
        self.kind = kind
        self.available = available
    }
}

extension ExamType {
    /// The exam paper's 大問 list for a specific level, in paper order — the real
    /// per-level structure (漢検 級 / JLPT レベル). Data-backed sections are playable;
    /// the rest are shown for accuracy and marked 준비 중.
    public func sections(for level: String) -> [ExamSection] {
        var list = self == .kanken ? Self.kankenSections(level) : Self.jlptSections(level)
        let numerals = self.numerals(count: list.count)
        for i in list.indices { list[i].numeral = numerals[i] }
        return list
    }

    /// 大問 markers in paper order: 漢検 uses Japanese numerals, JLPT uses 問題 numbers.
    private func numerals(count: Int) -> [String] {
        switch self {
        case .kanken:
            let kanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
            return (0..<count).map { $0 < kanji.count ? kanji[$0] : "\($0 + 1)" }
        case .jlpt:
            return (0..<count).map { "\($0 + 1)" }
        }
    }

    // MARK: Section catalog

    /// A data-backed, playable section.
    private static func live(_ id: String, _ ja: String, _ type: KankenQuestionType,
                             _ kind: String?) -> ExamSection {
        ExamSection(id: id, numeral: "", jaTitle: ja, renderType: type, kind: kind, available: true)
    }
    /// A real 大問 whose curated data isn't ready — shown for structure, not playable.
    private static func soon(_ id: String, _ ja: String) -> ExamSection {
        ExamSection(id: id, numeral: "", jaTitle: ja, renderType: .comingSoon, kind: nil, available: false)
    }
    private static var reading: ExamSection { live("reading", "読み", .reading, "reading") }
    private static var writing: ExamSection { live("writing", "書き取り", .writing, "orthography") }
    private static var radical: ExamSection { live("radical", "部首", .radical, nil) }
    private static var strokes: ExamSection { live("strokes", "画数", .strokes, nil) }
    private static var yoji: ExamSection { live("yoji", "四字熟語", .yojijukugo, nil) }
    private static func okuri(_ ja: String) -> ExamSection { live("okuri", ja, .okurigana, nil) }
    /// 対義語・類義語 — live only where the dataset covers (5級〜2級).
    private static var taigirui: ExamSection { live("taigirui", "対義語・類義語", .taigirui, nil) }
    private static var onkun: ExamSection { live("onkun", "音読み・訓読み", .onkun, nil) }
    /// 筆順 — the glyph with one stroke marked; the answer is its place in
    /// writing order. Generated from the KanjiVG paths, so no bank kind.
    private static var hitsujun: ExamSection { live("hitsujun", "筆順", .hitsujun, nil) }
    /// 同音異字 / 同音・同訓異字 — pick the right kanji among homophones. Same
    /// blank-fill rendering as 書き取り, drawing on the generated bank.
    private static func doon(_ ja: String) -> ExamSection {
        live("doonkun", ja, .writing, "doonkun")
    }
    /// 漢字識別 — three words missing the same kanji; pick the one that fits
    /// all three. Blank-fill with kanji options, so it renders like 書き取り.
    private static var shikibetsu: ExamSection {
        live("shikibetsu", "漢字識別", .writing, "shikibetsu")
    }
    private static var sanji: ExamSection { live("sanji", "三字熟語", .writing, "sanji") }
    private static var kyotsu: ExamSection {
        live("common-kanji", "共通の漢字", .writing, "kyotsu")
    }
    /// 反対のことば / 対義語 — the answer is a whole word, so it renders like
    /// 対義語・類義語 rather than as a single-kanji blank.
    private static func hantai(_ id: String, _ ja: String, _ kind: String) -> ExamSection {
        live(id, ja, .taigirui, kind)
    }
    private static func authored(_ id: String, _ ja: String, _ kind: String,
                                 _ type: KankenQuestionType = .writing) -> ExamSection {
        live(id, ja, type, kind)
    }

    /// 漢検 papers in official 大問 order.
    private static func kankenSections(_ level: String) -> [ExamSection] {
        switch level {
        case "10級":
            return [reading, hitsujun, strokes,
                    hantai("hantai", "反対のことば", "hantai"), writing]
        case "9級":
            return [reading, hitsujun, strokes, okuri("送りがな"),
                    hantai("hantai", "反対のことば", "hantai"), writing]
        case "8級":
            return [reading, onkun, radical, strokes,
                    okuri("送りがな"), hantai("taigi", "対義語", "taigi"),
                    doon("同音異字"), writing]
        case "7級":
            return [reading, onkun, radical, strokes,
                    okuri("送りがな"), hantai("taigi", "対義語", "taigi"),
                    doon("同音異字"), sanji, writing]
        case "6級":
            return [reading, onkun, radical, strokes,
                    okuri("送りがな"), taigirui,
                    doon("同音・同訓異字"), authored("tsukuri", "熟語作り", "tsukuri"), writing]
        case "5級":
            return [reading, radical, strokes, okuri("送りがな"),
                    taigirui, authored("kousei", "熟語の構成", "kousei"),
                    onkun, yoji,
                    doon("同音・同訓異字"), writing]
        case "4級", "3級":
            return [reading, doon("同音・同訓異字"), shikibetsu,
                    authored("kousei", "熟語の構成", "kousei"), radical, taigirui,
                    okuri("漢字と送りがな"), yoji,
                    authored("goji", "誤字訂正", "goji"), writing]
        case "準2級", "2級":
            return [reading, radical, authored("kousei", "熟語の構成", "kousei"), yoji,
                    taigirui, doon("同音・同訓異字"),
                    authored("goji", "誤字訂正", "goji"), okuri("漢字と送りがな"), writing]
        case "準1級":
            return [
                reading,
                authored("hyogai-reading", "表外の読み", "hyogai", .reading),
                soon("jukugo-reading", "熟語の読み・一字訓読み"),
                kyotsu,
                writing,
                authored("goji", "誤字訂正", "goji"),
                yoji,
                taigirui,
                authored("koji-kotowaza", "故事・諺", "kotowaza"),
                soon("passage", "文章題"),
            ]
        case "1級":
            return [
                reading,
                writing,
                authored("word-selection", "語選択", "goselect"),
                yoji,
                authored("jukujikun-ateji", "熟字訓・当て字", "jukujikun", .reading),
                onkun,
                taigirui,
                authored("koji-kotowaza", "故事・諺", "kotowaza"),
                soon("passage", "文章題"),
            ]
        default:
            return [reading, radical, writing]
        }
    }

    /// JLPT N5〜N1 文字・語彙 sections (問題1〜, per the official 大問のねらい).
    private static func jlptSections(_ level: String) -> [ExamSection] {
        let reading = live("reading", "漢字読み", .reading, "reading")
        let hyoki = live("orthography", "表記", .writing, "orthography")
        let bunmyaku = live("context", "文脈規定", .context, "context")
        switch level {
        case "N5":
            return [reading, hyoki, bunmyaku, live("iikae", "言い換え類義", .taigirui, "iikae")]
        case "N4", "N3":
            return [reading, hyoki, bunmyaku, live("iikae", "言い換え類義", .taigirui, "iikae"), soon("youhou", "用法")]
        case "N2":
            return [reading, hyoki, live("gokeisei", "語形成", .writing, "gokeisei"), bunmyaku,
                    live("iikae", "言い換え類義", .taigirui, "iikae"), soon("youhou", "用法")]
        case "N1":
            return [reading, bunmyaku, live("iikae", "言い換え類義", .taigirui, "iikae"), soon("youhou", "用法")]
        default:
            return [reading, hyoki, bunmyaku]
        }
    }
}

/// A ready-to-show 漢検 multiple-choice question. Adapted from the pre-authored
/// `JLPTQuestion` bank (読み・書き取り) or generated from kanji data (部首). Codable
/// so a missed one can be stored in the 오답노트 and re-served without a re-query.
public struct KankenQuestion: Equatable, Identifiable, Sendable, Codable {
    public let id: String            // stable: "<type>:<kanjiID>:<sourceID>"
    public let type: KankenQuestionType
    public let kanjiID: Int
    public let prompt: String        // the sentence / kanji glyph shown
    public let focus: String?        // substring of `prompt` to underline
    public let options: [String]
    public let answer: String        // the correct option's text
    public let explanation: String?
    public let label: String?        // overrides the type's prompt label (e.g. 読み/意味)
    /// 筆順 only: the glyph's strokes in order, and which one the question marks.
    /// Carried on the question rather than re-fetched so a 오답노트 entry still
    /// renders offline, which is the whole point of storing the question.
    public let strokePaths: [String]?
    public let markedStroke: Int?

    public init(
        id: String, type: KankenQuestionType, kanjiID: Int, prompt: String,
        focus: String? = nil, options: [String], answer: String,
        explanation: String? = nil, label: String? = nil,
        strokePaths: [String]? = nil, markedStroke: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.kanjiID = kanjiID
        self.prompt = prompt
        self.focus = focus
        self.options = options
        self.answer = answer
        self.explanation = explanation
        self.label = label
        self.strokePaths = strokePaths
        self.markedStroke = markedStroke
    }
}

/// A kanji with its strokes in writing order — the input to the 筆順 generator.
public struct StrokeOrderItem: Equatable, Sendable {
    public let kanjiID: Int
    public let literal: String
    public let paths: [String]

    public init(kanjiID: Int, literal: String, paths: [String]) {
        self.kanjiID = kanjiID
        self.literal = literal
        self.paths = paths
    }
}

/// A raw kanji + its radical, the input to the 部首 question generator (the
/// feature builds the multiple choice from a pool of real radicals).
public struct RadicalItem: Equatable, Sendable {
    public let kanjiID: Int
    public let literal: String
    public let radical: String

    public init(kanjiID: Int, literal: String, radical: String) {
        self.kanjiID = kanjiID
        self.literal = literal
        self.radical = radical
    }
}

/// A missed 漢検 question saved to the 오답노트, with the day it was saved so the
/// notebook can show newest-first. The whole question is stored so it re-serves
/// offline without touching the DB.
public struct WrongNote: Equatable, Identifiable, Sendable, Codable {
    public var id: String { question.id }
    public let question: KankenQuestion
    public let savedDay: Int

    public init(question: KankenQuestion, savedDay: Int) {
        self.question = question
        self.savedDay = savedDay
    }
}

import Foundation

/// One of the 漢検 exam's 大問 question types. Phase 1 ships the three that come
/// from real, vetted data (読み・部首・書き取り); the rest are curated later.
public enum KankenQuestionType: String, CaseIterable, Sendable, Equatable, Codable {
    case reading          // 一 読み
    case radical          // 二 部首
    case writing          // 九 書き取り
    // Phase 2 (curated data):
    // case compound      // 三 熟語の構成
    // case yojijukugo    // 四 四字熟語
    // case antonymSynonym// 五 対義・類義
    // case homophone     // 六 同音・同訓異字
    // case errorFix      // 七 誤字訂正
    // case okurigana     // 八 送りがな

    /// The 大問 number label (Japanese numeral), e.g. "一".
    public var numeral: String {
        switch self {
        case .reading: "一"
        case .radical: "二"
        case .writing: "九"
        }
    }

    /// The Japanese section name, as printed on the exam.
    public var jaTitle: String {
        switch self {
        case .reading: "読み"
        case .radical: "部首"
        case .writing: "書き取り"
        }
    }

    /// Whether the multiple-choice options are Japanese text (readings / kanji) —
    /// so the card renders them in the Japanese face.
    public var japaneseOptions: Bool { true }
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

    public init(
        id: String, type: KankenQuestionType, kanjiID: Int, prompt: String,
        focus: String? = nil, options: [String], answer: String, explanation: String? = nil
    ) {
        self.id = id
        self.type = type
        self.kanjiID = kanjiID
        self.prompt = prompt
        self.focus = focus
        self.options = options
        self.answer = answer
        self.explanation = explanation
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

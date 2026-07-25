import Foundation

/// How a question renders in the player: a radical pick (kanji glyph + 部首
/// options) vs. a sentence prompt (reading / orthography / context). Also tags a
/// stored `KankenQuestion` so the 오답노트 knows how to draw it.
public enum KankenQuestionType: String, CaseIterable, Sendable, Equatable, Codable {
    case reading          // 読み / 漢字読み — sentence, answer is a reading
    case radical          // 部首 — kanji glyph, options are 部首 glyphs
    case writing          // 書き取り / 表記 — sentence, answer is a kanji spelling
    case context          // 文脈規定 — sentence cloze

    /// Reading answers get slightly larger option type than kanji/word answers.
    public var isReading: Bool { self == .reading }
}

/// One selectable section of an exam's question paper — its label, the 大問 marker
/// shown on the card, how its questions render, and where they come from (a bank
/// `kind`, or the radical generator when `kind` is nil). Exam-specific: JLPT and
/// 漢検 expose different section lists (see `ExamType.sections`).
public struct ExamSection: Equatable, Sendable, Identifiable {
    public let id: String            // stable per section, unique within an exam
    public let numeral: String       // 大問 marker ("一" / "1" …)
    public let jaTitle: String       // section name as printed on the exam
    public let renderType: KankenQuestionType
    public let kind: String?         // bank kind to query; nil = radical-generated

    public init(id: String, numeral: String, jaTitle: String,
                renderType: KankenQuestionType, kind: String?) {
        self.id = id
        self.numeral = numeral
        self.jaTitle = jaTitle
        self.renderType = renderType
        self.kind = kind
    }
}

extension ExamType {
    /// The exam-question hub's section list. Only sections backed by real, vetted
    /// data ship today; curated ones (四字熟語 etc.) are added in Phase 2.
    public var sections: [ExamSection] {
        switch self {
        case .kanken:
            return [
                ExamSection(id: "reading", numeral: "一", jaTitle: "読み",
                            renderType: .reading, kind: "reading"),
                ExamSection(id: "radical", numeral: "二", jaTitle: "部首",
                            renderType: .radical, kind: nil),
                ExamSection(id: "writing", numeral: "九", jaTitle: "書き取り",
                            renderType: .writing, kind: "orthography"),
            ]
        case .jlpt:
            return [
                ExamSection(id: "reading", numeral: "1", jaTitle: "漢字読み",
                            renderType: .reading, kind: "reading"),
                ExamSection(id: "orthography", numeral: "2", jaTitle: "表記",
                            renderType: .writing, kind: "orthography"),
                ExamSection(id: "context", numeral: "3", jaTitle: "文脈規定",
                            renderType: .context, kind: "context"),
            ]
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

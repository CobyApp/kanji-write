import Foundation

/// Heuristic word / 表現(expression) split — the bundled DB has no POS column, so
/// a phrase is detected by a mid-string kana particle (お世話になる, 油を売る); a plain
/// vocabulary word (世界, 動く) has none. Pure-kanji words and okurigana words
/// (trailing kana only) are never flagged.
public func isExpressionSurface(_ surface: String) -> Bool {
    let particles: Set<Character> = ["は", "が", "を", "に", "へ", "と", "も", "の", "で", "や"]
    let chars = Array(surface)
    guard chars.count >= 3 else { return false }
    for i in 0..<(chars.count - 1) where particles.contains(chars[i]) { return true }
    return false
}

/// A usage word that contains a kanji (from JMdict).
public struct WordEntry: Equatable, Identifiable, Sendable {
    public let id: Int
    public let surface: String
    public let reading: String
    public let meaningEn: String?
    public let meaningKo: String?
    public let meaningJa: String?
    public let meaningZh: String?

    public init(
        id: Int, surface: String, reading: String, meaningEn: String?,
        meaningKo: String? = nil, meaningJa: String? = nil, meaningZh: String? = nil
    ) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.meaningEn = meaningEn
        self.meaningKo = meaningKo
        self.meaningJa = meaningJa
        self.meaningZh = meaningZh
    }
}

/// A Japanese example sentence with translations keyed by language code.
public struct ExampleSentence: Equatable, Identifiable, Sendable {
    public let id: Int
    public let textJa: String
    public let translations: [String: String]

    public init(id: Int, textJa: String, translations: [String: String]) {
        self.id = id
        self.textJa = textJa
        self.translations = translations
    }
}

/// An antonym or related word surfaced for a kanji.
public struct RelationEntry: Equatable, Identifiable, Sendable {
    public var id: String { "\(type):\(surface)" }
    public let surface: String
    public let type: String   // "antonym" | "related"

    public init(surface: String, type: String) {
        self.surface = surface
        self.type = type
    }
}

/// A pre-authored JLPT 文字・語彙 question about a kanji: a Japanese prompt, four
/// options, the index of the correct one, and a native-language explanation
/// (해설). Generated offline into the bundled DB — no runtime distractor building.
public struct JLPTQuestion: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kanjiID: Int
    public let level: String
    public let kind: String      // "reading" | "orthography" | "context"
    public let prompt: String
    public let options: [String]
    public let answer: Int       // index into `options`
    public let explanations: [String: String]  // lang code → 해설 (ko/ja/zh/en)
    public let focus: String?    // substring of `prompt` to underline (target word)

    public init(
        id: Int, kanjiID: Int, level: String, kind: String,
        prompt: String, options: [String], answer: Int,
        explanations: [String: String], focus: String? = nil
    ) {
        self.id = id
        self.kanjiID = kanjiID
        self.level = level
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.answer = answer
        self.explanations = explanations
        self.focus = focus
    }

    /// The correct option's text.
    public var answerText: String {
        options.indices.contains(answer) ? options[answer] : (options.first ?? "")
    }
    /// Prompt with any `<u>…</u>` tags stripped for display.
    public var promptClean: String { JLPTQuestion.parseUnderline(prompt).clean }
    /// The word to underline: the `<u>`-wrapped text, else the focus column.
    public var underlineTarget: String? { JLPTQuestion.parseUnderline(prompt).target ?? focus }

    /// Strips `<u>…</u>` and returns the cleaned prompt + wrapped substring.
    public static func parseUnderline(_ raw: String) -> (clean: String, target: String?) {
        guard let open = raw.range(of: "<u>"), let close = raw.range(of: "</u>"),
              open.upperBound <= close.lowerBound else { return (raw, nil) }
        let target = String(raw[open.upperBound..<close.lowerBound])
        let clean = raw.replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
        return (clean, target.isEmpty ? nil : target)
    }
}

/// An antonym pair anchored to a kanji: a word that contains the kanji
/// (`prompt`) and its opposite (`answer`). Powers the "pick the antonym" quiz.
public struct AntonymPair: Equatable, Identifiable, Sendable {
    public var id: String { "\(promptSurface):\(answerSurface)" }
    public let promptSurface: String
    public let promptReading: String
    public let answerSurface: String

    public init(promptSurface: String, promptReading: String, answerSurface: String) {
        self.promptSurface = promptSurface
        self.promptReading = promptReading
        self.answerSurface = answerSurface
    }
}

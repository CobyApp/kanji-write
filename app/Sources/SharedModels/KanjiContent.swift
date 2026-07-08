import Foundation

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

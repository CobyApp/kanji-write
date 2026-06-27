import Foundation

/// A usage word that contains a kanji (from JMdict).
public struct WordEntry: Equatable, Identifiable, Sendable {
    public let id: Int
    public let surface: String
    public let reading: String
    public let meaningEn: String?
    public let meaningKo: String?

    public init(id: Int, surface: String, reading: String, meaningEn: String?, meaningKo: String? = nil) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.meaningEn = meaningEn
        self.meaningKo = meaningKo
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

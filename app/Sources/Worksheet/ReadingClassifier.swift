import Foundation
import SharedModels

/// Which reading of a kanji a word uses.
public enum ReadingKind: String, Equatable, Sendable {
    case on
    case kun
}

/// Converts a katakana string to hiragana, so on'yomi (stored in katakana) can
/// be compared against a word's hiragana reading.
private func toHiragana(_ s: String) -> String {
    s.applyingTransform(.hiraganaToKatakana, reverse: true) ?? s
}

/// Best-guess whether `word` reads `kanji` with its on'yomi or kun'yomi.
///
/// On'yomi are matched as katakana→hiragana; kun'yomi as the stem before the
/// KANJIDIC okurigana dot (e.g. `い.きる` → `い`), stripped of `-` markers. The
/// kind whose matched reading is the longest (most specific) wins, so a compound
/// like 学生 (がく**せい**) classifies as on'yomi even though a short kun stem
/// might also appear. Returns nil when neither reading is found — a heuristic,
/// since the data has no per-word reading tag (rendaku/sound changes can hide a
/// match).
public func classifyReading(word: WordEntry, kanji: Kanji) -> ReadingKind? {
    let reading = toHiragana(word.reading)
    guard !reading.isEmpty else { return nil }
    var best: (kind: ReadingKind, length: Int)?

    func consider(_ kind: ReadingKind, _ form: String) {
        guard !form.isEmpty, reading.contains(form) else { return }
        if best == nil || form.count > best!.length { best = (kind, form.count) }
    }
    for on in kanji.onReadings { consider(.on, toHiragana(on)) }
    for kun in kanji.kunReadings {
        let stem = kun.split(separator: ".").first.map(String.init) ?? kun
        consider(.kun, stem.replacingOccurrences(of: "-", with: ""))
    }
    return best?.kind
}

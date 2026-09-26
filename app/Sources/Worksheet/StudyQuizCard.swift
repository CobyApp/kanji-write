import DesignSystem
import SharedModels
import SwiftUI

/// One quick multiple-choice recall check mixed into the study deck. It quizzes
/// a single facet of the current kanji — its meaning, 음독(on) / 훈독(kun)
/// reading, or a related word's meaning / reading — so the material sticks.
/// Selection state resets each time the card is shown (the deck re-creates it
/// via `.id`), so revisiting re-quizzes.
struct StudyQuizCard: View {
    let spec: StudyQuizSpec
    let language: AppLanguage
    @State private var choice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            subject
            options
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Palette.lavender.opacity(0.28), lineWidth: 1.5))
        .shadow(color: Palette.lavender.opacity(0.10), radius: 30, x: 0, y: 0)
        .shadow(color: Palette.lavender.opacity(0.09), radius: 16, x: 0, y: 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Palette.lavender)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(L.worksheetQuiz[language])
                .font(.kawaii(17, weight: .bold, language: language)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
    }

    /// The thing being asked about: a kanji glyph, or a word (with furigana,
    /// unless the reading is the answer — then it's hidden).
    @ViewBuilder private var subject: some View {
        VStack(spacing: 12) {
            switch spec.subject {
            case let .kanji(glyph):
                Text(glyph)
                    .font(.kawaiiJP(76, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink)
            case let .word(surface, reading):
                if let reading, !reading.isEmpty {
                    RubyWord(surface, reading: reading, size: 30)
                } else {
                    Text(surface)
                        .font(.kawaiiJP(40, weight: .bold)).japaneseGlyphs()
                        .foregroundStyle(Palette.ink)
                }
            case let .sentence(text, focus):
                sentenceText(text, focus: focus)
                    .font(.kawaiiJP(sentenceSize(text), weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(spec.prompt)
                .font(.kawaii(15, language: language)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    /// A JLPT-style prompt with its target word underlined + accented.
    private func sentenceText(_ prompt: String, focus: String?) -> Text {
        guard let focus, !focus.isEmpty, let range = prompt.range(of: focus) else { return Text(prompt) }
        let before = String(prompt[..<range.lowerBound])
        let target = String(prompt[range])
        let after = String(prompt[range.upperBound...])
        return Text(before) + Text(target).underline().foregroundColor(Palette.pink) + Text(after)
    }

    private func sentenceSize(_ s: String) -> CGFloat {
        switch s.count { case 0...4: 38; case 5...12: 26; default: 20 }
    }

    private func optionFont() -> Font {
        // Japanese answers (readings / words) render in the Japanese face; meaning
        // answers use the app-language face.
        spec.japaneseOptions ? .kawaiiJP(17, weight: .bold) : .kawaii(16, weight: .bold, language: language)
    }

    private var options: some View {
        VStack(spacing: 10) {
            ForEach(spec.options, id: \.self) { option in
                Button { if choice == nil { choice = option } } label: {
                    HStack {
                        Text(option)
                            .font(optionFont()).japaneseGlyphs()
                            .foregroundStyle(optionText(option)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if choice != nil, option == spec.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mintDeep)
                        } else if option == choice {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.pinkDeep)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(optionFill(option))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(optionStroke(option), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(choice != nil)
            }
        }
        .sensoryFeedback(trigger: choice) { _, new in
            guard let new else { return nil }
            return new == spec.answer ? .success : .error
        }
    }

    // Neutral until answered, then green (correct) / red (chosen wrong).
    private func optionText(_ option: String) -> Color {
        guard choice != nil else { return Palette.ink }
        if option == spec.answer { return Palette.mintDeep }
        if option == choice { return Palette.pinkDeep }
        return Palette.inkSoft
    }
    private func optionFill(_ option: String) -> Color {
        guard choice != nil else { return Palette.background }
        if option == spec.answer { return Palette.mintSoft }
        if option == choice { return Palette.pinkSoft }
        return Palette.background
    }
    private func optionStroke(_ option: String) -> Color {
        guard choice != nil else { return Palette.ink.opacity(0.08) }
        if option == spec.answer { return Palette.mint }
        if option == choice { return Palette.pink }
        return .clear
    }
}

/// A study mini-quiz: what to show, the prompt, the options and the answer.
struct StudyQuizSpec: Equatable {
    /// What the learner is shown and asked about.
    enum Subject: Equatable {
        case kanji(String)                       // a kanji glyph
        case word(String, reading: String?)      // a word; reading hidden when it's the answer
        case sentence(String, focus: String?)    // a JLPT-style prompt; focus is underlined
    }
    var subject: Subject
    var prompt: String
    var options: [String]
    var answer: String
    /// Options are Japanese text (readings / words) → render in the Japanese face.
    var japaneseOptions: Bool
}

/// A deterministic RNG so a kanji's quiz options keep a stable order across the
/// many times SwiftUI re-evaluates the deck (no flicker / reshuffle).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

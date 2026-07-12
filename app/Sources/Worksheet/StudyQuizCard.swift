import DesignSystem
import SharedModels
import SwiftUI

/// One quick multiple-choice recall check mixed into the study deck: the learner
/// picks the meaning of the kanji (or one of its words) before moving on, so the
/// material sticks. Selection state resets each time the card is shown (the deck
/// re-creates it via `.id`), so revisiting re-quizzes.
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

    /// The thing being asked about: a kanji glyph, or a word (surface + reading).
    @ViewBuilder private var subject: some View {
        VStack(spacing: 12) {
            if let surface = spec.wordSurface {
                RubyWord(surface, reading: spec.wordReading ?? "", size: 30)
            } else {
                Text(spec.glyph)
                    .font(.kawaiiJP(76, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink)
            }
            Text(spec.prompt)
                .font(.kawaii(15, language: language)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var options: some View {
        VStack(spacing: 10) {
            ForEach(spec.options, id: \.self) { option in
                Button { if choice == nil { choice = option } } label: {
                    HStack {
                        Text(option)
                            .font(.kawaii(16, weight: .bold, language: language))
                            .foregroundStyle(optionText(option)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if choice != nil, option == spec.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                        } else if option == choice {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.pink)
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
    }

    // Neutral until answered, then green (correct) / red (chosen wrong).
    private func optionText(_ option: String) -> Color {
        guard choice != nil else { return Palette.ink }
        if option == spec.answer { return Palette.mint }
        if option == choice { return Palette.pink }
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

/// A study mini-quiz: the subject to show plus its options and correct answer.
struct StudyQuizSpec: Equatable {
    var glyph: String
    var wordSurface: String?
    var wordReading: String?
    var prompt: String
    var options: [String]
    var answer: String
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

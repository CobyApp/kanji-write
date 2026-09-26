import DesignSystem
import PencilKit
import SharedModels
import SwiftUI
import WritingCanvas

// The answering UI shared by the exam hub's player and the daily review quiz:
// the option list, typed readings, handwritten 書き取り, the explanation card and
// the progress strip. Each input view keeps its own draft state; the parent
// gives it `.id(attempt)` so a new attempt — including a missed question coming
// straight back — starts from a clean field or canvas.

/// Four (or five, for 熟語の構成) options labelled ア〜オ, coloured once answered.
struct ExamOptionList: View {
    let options: [String]
    let answer: String
    let chosen: String?
    var isReading = false
    let language: AppLanguage
    let onChoose: (String) -> Void

    private var answered: Bool { chosen != nil }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                Button { onChoose(option) } label: {
                    HStack(spacing: 12) {
                        Text(["ア", "イ", "ウ", "エ", "オ", "カ"][min(index, 5)])
                            .font(.kawaiiJP(14, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                        Text(option)
                            .font(.kawaiiJP(optionSize, weight: .bold)).japaneseGlyphs()
                            .foregroundStyle(textColor(option)).multilineTextAlignment(.leading)
                            // 用法's options are whole sentences; without this the
                            // HStack gives them one line and clips the rest.
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if answered, option == answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mintDeep)
                        } else if answered, option == chosen {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.pinkDeep)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(fill(option))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(stroke(option), lineWidth: 2))
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(answered)
                .accessibilityValue(accessibilityState(option))
            }
        }
    }

    /// Sentences (用法) get sentence-sized type; words and readings stay big.
    private var optionSize: CGFloat {
        let longest = options.map(\.count).max() ?? 0
        if longest > 12 { return 15 }
        return isReading ? 22 : 20
    }

    private func accessibilityState(_ option: String) -> String {
        guard answered else { return "" }
        if option == answer { return L.quizCorrect[language] }
        if option == chosen { return L.quizWrong[language] }
        return ""
    }
    private func textColor(_ option: String) -> Color {
        guard answered else { return Palette.ink }
        if option == answer { return Palette.mintDeep }
        if option == chosen { return Palette.pinkDeep }
        return Palette.inkSoft
    }
    private func fill(_ option: String) -> Color {
        guard answered else { return Palette.card }
        if option == answer { return Palette.mintSoft }
        if option == chosen { return Palette.pinkSoft }
        return Palette.card
    }
    private func stroke(_ option: String) -> Color {
        guard answered else { return Palette.ink.opacity(0.08) }
        if option == answer { return Palette.mint }
        if option == chosen { return Palette.pink }
        return .clear
    }
}

/// A kana field for 読み: the real paper has the reading written, not chosen.
struct TypedReadingAnswer: View {
    let answer: String
    let chosen: String?
    let language: AppLanguage
    /// Called with the normalized input, or with `answer` itself on a match.
    let onSubmit: (String) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool

    private var answered: Bool { chosen != nil }

    var body: some View {
        VStack(spacing: 12) {
            TextField(L.typeReadingPlaceholder[language], text: $typed)
                .font(.kawaiiJP(24, weight: .bold)).japaneseGlyphs()
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(submit)
                .padding(.vertical, 16).padding(.horizontal, 12)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: 2))
                .disabled(answered)
            if !answered {
                ExamPrimaryButton(title: L.checkAnswer[language], language: language, action: submit)
                    .disabled(ExamKana.normalize(typed).isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private var borderColor: Color {
        guard let chosen else { return Palette.ink.opacity(0.10) }
        return chosen == answer ? Palette.mint : Palette.pink
    }

    private func submit() {
        let input = ExamKana.normalize(typed)
        guard !input.isEmpty, !answered else { return }
        focused = false
        onSubmit(input == ExamKana.normalize(answer) ? answer : input)
    }
}

/// Handwritten 書き取り: write on the canvas, reveal the answer, mark it ○ / ×.
struct HandwrittenAnswer: View {
    let answer: String
    let answered: Bool
    let language: AppLanguage
    let onMark: (Bool) -> Void

    @State private var drawing = PKDrawing()
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                PencilCanvasView(drawing: $drawing)
                    .frame(height: 200)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Palette.ink.opacity(0.10), lineWidth: 2))
                    .allowsHitTesting(!revealed)
                Button { drawing = PKDrawing() } label: {
                    Image(systemName: "eraser")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L.clearCanvas[language])
                .disabled(revealed)
            }
            if !revealed {
                ExamPrimaryButton(title: L.revealAnswer[language], language: language) { revealed = true }
            } else if !answered {
                VStack(spacing: 10) {
                    Text(answer)
                        .font(.kawaiiJP(40, weight: .bold)).japaneseGlyphs()
                        .foregroundStyle(Palette.ink)
                    Text(L.selfMarkPrompt[language])
                        .font(.kawaii(14, language: language)).foregroundStyle(Palette.inkSoft)
                    HStack(spacing: 12) {
                        markButton(L.selfMarkWrong[language], icon: "xmark", color: Palette.pinkDeep) {
                            onMark(false)
                        }
                        markButton(L.selfMarkRight[language], icon: "checkmark", color: Palette.mintDeep) {
                            onMark(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .roundedCard()
            }
        }
    }

    private func markButton(_ title: String, icon: String, color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.kawaii(16, weight: .bold, language: language))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(color).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }
}

/// Right / wrong banner, the learner's typed answer when it was wrong, and the
/// authored explanation.
struct ExamExplanationCard: View {
    let isCorrect: Bool
    let chosen: String?
    let options: [String]
    let answer: String
    let explanation: String?
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(isCorrect ? L.quizCorrect[language] : L.quizWrong[language])
                    .font(.kawaii(15, weight: .bold))
            }
            .foregroundStyle(isCorrect ? Palette.mintDeep : Palette.pinkDeep)
            // A typed answer that was wrong isn't one of the options, so it
            // isn't marked anywhere else; show it next to the right one.
            if !isCorrect, let chosen, chosen != ExamKana.selfMarkedWrong, !options.contains(chosen) {
                Text("\(L.yourAnswer[language]): \(chosen)　→　\(answer)")
                    .font(.kawaiiJP(16, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink)
            }
            if let explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.kawaii(14, language: language)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundedCard()
        .accessibilityElement(children: .combine)
    }
}

/// The accent capsule button used for 채점 / 다음 / 정답 확인.
struct ExamPrimaryButton: View {
    let title: String
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kawaii(16, weight: .bold, language: language)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Palette.accent).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }
}

/// The prompt with its target word underlined, and any gloss line set small.
struct ExamPromptText: View {
    let prompt: String
    let focus: String?
    let language: AppLanguage

    var body: some View {
        let lines = prompt.components(separatedBy: "\n")
        VStack(spacing: 6) {
            underlined(lines[0])
                .font(.kawaiiJP(Self.size(for: lines[0]), weight: .bold)).japaneseGlyphs()
                .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if lines.count > 1 {
                // A generated gloss — the reading under an idiom, the meaning
                // under a 送りがな word. A hint, not the question.
                Text(lines.dropFirst().joined(separator: "\n"))
                    .font(.kawaii(16, language: language)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func underlined(_ text: String) -> Text {
        guard let focus, !focus.isEmpty, let range = text.range(of: focus) else { return Text(text) }
        return Text(String(text[..<range.lowerBound]))
            + Text(String(text[range])).underline().foregroundColor(Palette.accent)
            + Text(String(text[range.upperBound...]))
    }

    static func size(for line: String) -> CGFloat {
        switch line.count { case 0...3: return 44; case 4...10: return 30; default: return 22 }
    }
}

enum ExamKana {
    /// What a self-marked miss records as the chosen option: never equal to an
    /// answer, and never shown to the learner.
    static let selfMarkedWrong = "\u{0}✗"

    static func isKanaOnly(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            (0x3041...0x309F).contains($0.value) || (0x30A0...0x30FF).contains($0.value)
        }
    }

    /// Hiragana, no spaces: typed ヒトツ, ひとつ and " ひとつ " all match ひとつ.
    static func normalize(_ text: String) -> String {
        let trimmed = text.filter { !$0.isWhitespace }
        return trimmed.applyingTransform(.hiraganaToKatakana, reverse: true) ?? trimmed
    }
}

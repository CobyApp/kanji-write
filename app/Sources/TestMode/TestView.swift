import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

/// The kanji gloss for the selected language, falling back deterministically.
/// (Reimplemented inline so TestMode does not depend on KanjiDetail.)
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

/// A quick recall review over FSRS-due kanji: read the meaning, recall the glyph
/// in your head (no large writing), reveal, then self-grade pass/fail. A compact
/// progress grid shows the whole due set at a glance.
public struct TestView: View {
    @Bindable public var store: StoreOf<TestFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: StoreOf<TestFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            AuroraBackground()
            content
            if store.isFinished { ConfettiView() }
        }
        .navigationTitle(L.test[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        if store.isFinished {
            doneCard
        } else if let kanji = store.current {
            ScrollView {
                VStack(spacing: 16) {
                    progressGrid.popIn(delay: 0.02)
                    promptCard.popIn(delay: 0.10)
                    if sizeClass == .compact {
                        // iPhone: pick the kanji from four choices.
                        choiceGrid(kanji).popIn(delay: 0.18)
                        if store.revealed {
                            answerCard(kanji)
                            nextButton(kanji)
                        }
                    } else {
                        // iPad: recall in your head, reveal, self-grade.
                        if store.revealed {
                            answerCard(kanji)
                            gradeButtons
                        } else {
                            showAnswerButton.popIn(delay: 0.18)
                        }
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.revealed)
                // Replay the entrance each time the card changes.
                .id(store.index)
            }
        }
    }

    // MARK: Progress — a compact dot grid of the whole due set

    private var progressGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(L.test[appLanguage], accent: Palette.lavender)
                Spacer()
                Text("\(min(store.index + 1, store.queue.count)) / \(store.queue.count)")
                    .font(.kawaii(15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26), spacing: 8)], spacing: 8) {
                ForEach(Array(store.queue.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(dotColor(index))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Palette.accent,
                                                 lineWidth: index == store.index ? 2.5 : 0))
                }
            }
        }
        .roundedCard()
    }

    private func dotColor(_ index: Int) -> Color {
        if index < store.index { return Palette.mint }        // graded
        if index == store.index { return Palette.lavender }   // current
        return Palette.inkSoft.opacity(0.2)                    // upcoming
    }

    // MARK: Prompt (meaning only; the glyph stays hidden until reveal)

    private var promptCard: some View {
        VStack(spacing: 10) {
            Text((sizeClass == .compact ? L.testChoosePrompt : L.testPrompt)[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
            Text(localizedGloss(store.glosses, appLanguage) ?? "…")
                .font(.kawaii(26, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .roundedCard()
    }

    private var showAnswerButton: some View {
        Button { store.send(.showAnswerTapped) } label: {
            Text(L.showAnswer[appLanguage])
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Palette.lavender, Palette.sky],
                                   startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
                .shadow(color: Palette.lavender.opacity(0.4), radius: 10, y: 5)
        }
        .buttonStyle(.bouncy)
    }

    private func answerCard(_ kanji: Kanji) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PastelTile(kanji.literal, soft: Palette.lavenderSoft, accent: Palette.lavender,
                           size: 72, fontSize: 44)
                SpeakButton(kanji.literal)
            }
            if !kanji.onReadings.isEmpty {
                readingRow(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
            }
            if !kanji.kunReadings.isEmpty {
                readingRow(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
            }
        }
        .frame(maxWidth: .infinity).transition(.scale.combined(with: .opacity))
        .roundedCard()
    }

    private func readingRow(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.kawaii(13, weight: .bold)).foregroundStyle(accent)
                .frame(width: 34, alignment: .leading)
            Text(readings.joined(separator: "、"))
                .font(.kawaii(16)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            gradeButton(L.fail[appLanguage], Palette.pink) { store.send(.graded(pass: false)) }
            gradeButton(L.pass[appLanguage], Palette.mint) { store.send(.graded(pass: true)) }
        }
    }

    // MARK: iPhone multiple-choice

    private func choiceGrid(_ answer: Kanji) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(store.options) { option in
                Button { store.send(.optionSelected(option.id)) } label: {
                    Text(option.literal)
                        .font(.kawaii(40, weight: .bold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).frame(height: 92)
                        .background(choiceFill(option, answer))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(choiceStroke(option, answer), lineWidth: 2))
                }
                .buttonStyle(.bouncy)
                .disabled(store.revealed)
            }
        }
    }

    /// After reveal: the correct choice turns mint, a wrong pick turns pink.
    private func choiceFill(_ option: Kanji, _ answer: Kanji) -> Color {
        guard store.revealed else { return Palette.card }
        if option.id == answer.id { return Palette.mintSoft }
        if option.id == store.selected { return Palette.pinkSoft }
        return Palette.card
    }

    private func choiceStroke(_ option: Kanji, _ answer: Kanji) -> Color {
        guard store.revealed else { return Palette.inkSoft.opacity(0.2) }
        if option.id == answer.id { return Palette.mint }
        if option.id == store.selected { return Palette.pink }
        return .clear
    }

    private func nextButton(_ answer: Kanji) -> some View {
        gradeButton(L.next[appLanguage], Palette.lavender) {
            store.send(.graded(pass: store.selected == answer.id))
        }
    }

    private func gradeButton(_ label: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [color, color.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
                .shadow(color: color.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.bouncy)
    }

    private var doneCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Sparkles()
                Text("🎉").font(.system(size: 52)).celebrate()
            }
            .frame(height: 80)
            Text(L.nothingDue[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.seeTomorrow[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
        .padding(16)
    }
}

import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct QuizView: View {
    @Bindable public var store: StoreOf<QuizFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    // Stamped when a quiz finishes so Home knows today's quiz is done.
    @AppStorage("lastQuizDay") private var lastQuizDay = -1
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: StoreOf<QuizFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle(L.quiz[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear(language: appLanguage)) }
        .onChange(of: store.isFinished) { _, finished in
            if finished { lastQuizDay = store.today }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isFinished {
            resultCard
        } else if let item = store.current {
            ScrollView {
                VStack(spacing: 20) {
                    progress
                    questionCard(item)
                    options(item)
                    if store.answered { explanationCard(item); nextButton }
                }
                .padding(16)
                .readableWidth(sizeClass)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.answered)
                .animation(.easeInOut, value: store.current?.id)
            }
        } else if !store.isLoading {
            emptyCard
        }
    }

    /// "총 12문제" — the total number of questions to solve this session.
    private var totalCountLabel: String {
        "\(L.quizTotalPrefix[appLanguage])\(store.totalItems)\(L.quizCountUnit[appLanguage])"
    }

    private var progress: some View {
        HStack(spacing: 8) {
            SectionHeader(L.quizPrompt[appLanguage], accent: Palette.lavender)
            Text(totalCountLabel)
                .font(.kawaii(11, weight: .bold)).foregroundStyle(Palette.lavender)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Palette.lavenderSoft).clipShape(Capsule())
            if store.isRetry {
                Text(L.quizRetry[appLanguage])
                    .font(.kawaii(11, weight: .bold)).foregroundStyle(Palette.pink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.pinkSoft).clipShape(Capsule())
            }
            Spacer()
            Text("\(store.mastered) / \(store.totalItems)")
                .font(.kawaii(15, weight: .bold)).monospacedDigit()
                .foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    private func questionCard(_ item: QuizItem) -> some View {
        VStack(spacing: 10) {
            Text(promptLabel(item.kind))
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            promptText(item)
                .font(.kawaiiJP(promptSize(item.prompt), weight: .bold))
                .japaneseGlyphs()
                .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .roundedCard()
    }

    /// The prompt with its target word (`focus`) underlined and accented, so it's
    /// unmistakable which word the question is about (e.g. the word to read).
    /// Split into before/target/after Texts so the underline reliably spans the
    /// whole target (every kanji), not just its first glyph.
    private func promptText(_ item: QuizItem) -> Text {
        guard let focus = item.focus, !focus.isEmpty,
              let range = item.prompt.range(of: focus) else { return Text(item.prompt) }
        let before = String(item.prompt[..<range.lowerBound])
        let target = String(item.prompt[range])
        let after = String(item.prompt[range.upperBound...])
        return Text(before)
            + Text(target).underline().foregroundColor(Palette.pink)
            + Text(after)
    }

    /// Short stems (a single word/reading) get big type; full sentences wrap at a
    /// smaller size so they stay on screen.
    private func promptSize(_ prompt: String) -> CGFloat {
        switch prompt.count {
        case 0...3: 44
        case 4...10: 30
        default: 22
        }
    }

    private func promptLabel(_ kind: String) -> String {
        switch kind {
        case "reading": L.quizWordReading[appLanguage]
        case "orthography": L.quizOrthography[appLanguage]
        case "youhou": L.quizUsage[appLanguage]
        default: L.quizCloze[appLanguage]
        }
    }

    /// Reading options render in the Japanese face; everything else too (options
    /// are Japanese words/readings from the bank). 用法 is the one kind whose
    /// options are whole sentences, so they take sentence-sized type.
    private func optionFont(_ item: QuizItem) -> Font {
        switch item.kind {
        case "reading": .kawaiiJP(22, weight: .bold)
        case "youhou": .kawaiiJP(15, weight: .semibold)
        default: .kawaiiJP(19, weight: .bold)
        }
    }

    private func options(_ item: QuizItem) -> some View {
        VStack(spacing: 12) {
            ForEach(item.options, id: \.self) { option in
                Button { store.send(.chose(option)) } label: {
                    HStack {
                        Text(option)
                            .font(optionFont(item))
                            .japaneseGlyphs()
                            .foregroundStyle(optionText(option, item))
                            .multilineTextAlignment(.leading)
                            // 用法 options are sentences; without this the HStack
                            // hands them one line and truncates the rest.
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if store.answered, option == item.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                        } else if store.answered, option == store.chosen {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.pink)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(optionFill(option, item))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(optionStroke(option, item), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(store.answered)
            }
        }
    }

    /// The 해설 shown once answered — correct/wrong banner + the authored reason.
    @ViewBuilder
    private func explanationCard(_ item: QuizItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: store.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(store.isCorrect ? Palette.mint : Palette.pink)
                Text(store.isCorrect ? L.quizCorrect[appLanguage] : L.quizWrong[appLanguage])
                    .font(.kawaii(15, weight: .bold))
                    .foregroundStyle(store.isCorrect ? Palette.mint : Palette.pink)
            }
            if let explanation = item.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundedCard()
    }

    private var nextButton: some View {
        Button { store.send(.next) } label: {
            Text(L.next[appLanguage])
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Palette.accent).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var resultCard: some View {
        let firstTry = store.firstAttempt.values.filter { $0 }.count
        return VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Palette.mint)
            Text(L.quizDone[appLanguage]).font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text("\(firstTry) / \(store.totalItems)")
                .font(.kawaii(30, weight: .bold)).monospacedDigit().foregroundStyle(Palette.mint)
            Text(L.quizFirstTry[appLanguage])
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            Button { store.send(.restart) } label: {
                Text(L.quizAgain[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Palette.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard().padding(16)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(Palette.mint)
            Text(L.quizNothingDue[appLanguage]).font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .roundedCard().padding(16)
    }

    // Option styling: neutral until answered, then green (correct) / red (chosen wrong).
    private func optionText(_ option: String, _ item: QuizItem) -> Color {
        guard store.answered else { return Palette.ink }
        if option == item.answer { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Palette.inkSoft
    }
    private func optionFill(_ option: String, _ item: QuizItem) -> Color {
        guard store.answered else { return Palette.card }
        if option == item.answer { return Palette.mintSoft }
        if option == store.chosen { return Palette.pinkSoft }
        return Palette.card
    }
    private func optionStroke(_ option: String, _ item: QuizItem) -> Color {
        guard store.answered else { return Palette.ink.opacity(0.08) }
        if option == item.answer { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Color.clear
    }
}

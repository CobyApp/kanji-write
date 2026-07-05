import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct QuizView: View {
    @Bindable public var store: StoreOf<QuizFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

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
                    if store.answered { nextButton }
                }
                .padding(16)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.answered)
                .animation(.easeInOut, value: store.current?.id)
            }
        } else if !store.isLoading {
            emptyCard
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            SectionHeader(L.quizPrompt[appLanguage], accent: Palette.lavender)
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
        VStack(spacing: 8) {
            Text(promptLabel(item.kind))
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            Text(item.prompt)
                .font(.kawaii(item.kind == .kanjiMeaning ? 60 : 40, weight: .bold))
                .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.kawaii(15, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .roundedCard()
    }

    private func promptLabel(_ kind: QuizKind) -> String {
        switch kind {
        case .kanjiMeaning: L.quizKanjiMeaning[appLanguage]
        case .wordReading: L.quizWordReading[appLanguage]
        case .wordMeaning: L.quizWordMeaning[appLanguage]
        }
    }

    private func options(_ item: QuizItem) -> some View {
        VStack(spacing: 12) {
            ForEach(item.options, id: \.self) { option in
                Button { store.send(.chose(option)) } label: {
                    HStack {
                        Text(option)
                            .font(.kawaii(item.kind == .wordReading ? 22 : 18, weight: .bold,
                                          language: item.kind == .wordMeaning ? appLanguage : .ja))
                            .foregroundStyle(optionText(option, item))
                            .multilineTextAlignment(.leading)
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

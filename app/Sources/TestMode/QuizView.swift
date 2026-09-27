import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

/// 오늘의 복습 — the daily spaced-repetition quiz. Same answering UI as the exam
/// hub: labelled options, typed readings and handwritten 書き取り in 직접 쓰기
/// mode, and misses filed into the 오답노트.
public struct QuizView: View {
    @Bindable public var store: StoreOf<QuizFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examWriteMode") private var writeMode = false
    // Stamped when a quiz finishes so Home knows today's quiz is done.
    @AppStorage("lastQuizDay") private var lastQuizDay = -1
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .sensoryFeedback(trigger: store.chosen) { _, new in
            guard new != nil else { return nil }
            return store.isCorrect ? .success : .error
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Palette.accent)
                Text(L.loadingQuestions[appLanguage])
                    .font(.kawaii(15, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.isFinished {
            ScrollView { resultCard.readableWidth(sizeClass) }
                .scrollIndicators(.hidden)
        } else if let item = store.current {
            ScrollView {
                VStack(spacing: 20) {
                    progress
                    questionCard(item)
                    answerArea(item)
                    if store.answered {
                        ExamExplanationCard(
                            isCorrect: store.isCorrect, chosen: store.chosen, options: item.options,
                            answer: item.answer, explanation: item.explanation, language: appLanguage)
                        ExamPrimaryButton(title: L.next[appLanguage], language: appLanguage) {
                            store.send(.next)
                        }
                    }
                }
                .padding(16)
                .readableWidth(sizeClass)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
                           value: store.answered)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        } else {
            emptyCard
        }
    }

    private var progress: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(L.reviewQuiz[appLanguage])
                    .font(.kawaii(15, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                if store.isRetry {
                    Text(L.quizRetry[appLanguage])
                        .font(.kawaii(11, weight: .bold)).foregroundStyle(Palette.pinkDeep)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.pinkSoft).clipShape(Capsule())
                }
                Spacer()
                Text("\(store.mastered) / \(store.totalItems)")
                    .font(.kawaii(15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
            }
            ProgressView(value: Double(store.mastered), total: Double(max(store.totalItems, 1)))
                .tint(Palette.accent)
        }
        .roundedCard()
        .accessibilityElement(children: .combine)
    }

    private func questionCard(_ item: QuizItem) -> some View {
        VStack(spacing: 10) {
            Text(promptLabel(item.kind))
                .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            ExamPromptText(prompt: item.prompt, focus: item.focus, language: appLanguage)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .roundedCard()
    }

    private func promptLabel(_ kind: String) -> String {
        switch kind {
        case "reading": L.quizWordReading[appLanguage]
        case "orthography": L.quizOrthography[appLanguage]
        case "youhou": L.quizUsage[appLanguage]
        default: L.quizCloze[appLanguage]
        }
    }

    @ViewBuilder
    private func answerArea(_ item: QuizItem) -> some View {
        Group {
            if writeMode, item.kind == "reading", ExamKana.isKanaOnly(item.answer) {
                TypedReadingAnswer(answer: item.answer, chosen: store.chosen, language: appLanguage) {
                    store.send(.chose($0))
                }
            } else if writeMode, item.kind == "orthography" {
                HandwrittenAnswer(answer: item.answer, answered: store.answered, language: appLanguage) {
                    store.send(.chose($0 ? item.answer : ExamKana.selfMarkedWrong))
                }
            } else {
                ExamOptionList(options: item.options, answer: item.answer, chosen: store.chosen,
                               isReading: item.kind == "reading", language: appLanguage) {
                    store.send(.chose($0))
                }
            }
        }
        .id(store.attempt)
    }

    private var resultCard: some View {
        let firstTry = store.firstAttempt.values.filter { $0 }.count
        let ratio = store.totalItems > 0 ? Double(firstTry) / Double(store.totalItems) : 0
        return VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Palette.mint)
            Text(L.quizDone[appLanguage])
                .font(.kawaii(18, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
            Text("\(Int((ratio * 100).rounded()))%")
                .font(.kawaii(30, weight: .bold)).monospacedDigit()
                .foregroundStyle(ratio >= 0.7 ? Palette.mintDeep : Palette.coralDeep)
            Text("\(L.quizFirstTry[appLanguage]) · \(firstTry) / \(store.totalItems)")
                .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            if firstTry < store.totalItems, !store.isReplay {
                Text(L.examMissedCount[appLanguage])
                    .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            ExamPrimaryButton(title: L.quizAgain[appLanguage], language: appLanguage) {
                store.send(.restart)
            }
            .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 16)
        .roundedCard().padding(16)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundStyle(Palette.mint)
            Text(L.quizNothingDue[appLanguage])
                .font(.kawaii(16, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .roundedCard().padding(16)
    }
}

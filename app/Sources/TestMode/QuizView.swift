import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

/// The word meaning for the selected language (falling back to English).
private func wordMeaning(_ word: WordEntry, _ language: AppLanguage) -> String? {
    switch language {
    case .ko: word.meaningKo ?? word.meaningEn
    case .ja: word.meaningJa ?? word.meaningEn
    case .zh: word.meaningZh ?? word.meaningEn
    case .en: word.meaningEn
    }
}

public struct QuizView: View {
    @Bindable public var store: StoreOf<QuizFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<QuizFeature>) {
        self.store = store
    }

    private var sourceBinding: Binding<Bool> {
        Binding(get: { store.useWordbook }, set: { store.send(.setWordbook($0)) })
    }

    public var body: some View {
        ZStack {
            AuroraBackground()
            content
        }
        .navigationTitle(L.quiz[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: sourceBinding) {
                    Text(L.level[appLanguage]).tag(false)
                    Text(L.wordbook[appLanguage]).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        if store.isFinished {
            resultCard
        } else if let word = store.current {
            ScrollView {
                VStack(spacing: 20) {
                    progress
                    questionCard(word)
                    options(word)
                    if store.answered { nextButton }
                }
                .padding(16)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.answered)
                .animation(.easeInOut, value: store.index)
            }
        } else if !store.isLoading {
            emptyCard
        }
    }

    private var progress: some View {
        HStack {
            SectionHeader(L.quizPrompt[appLanguage], accent: Palette.lavender)
            Spacer()
            Text("\(min(store.index + 1, store.total)) / \(store.total)")
                .font(.kawaii(15, weight: .bold)).monospacedDigit()
                .foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    private func questionCard(_ word: WordEntry) -> some View {
        VStack(spacing: 10) {
            Text(word.surface)
                .font(.kawaii(48, weight: .bold)).foregroundStyle(Palette.ink)
            if let meaning = wordMeaning(word, appLanguage), !meaning.isEmpty {
                Text(meaning)
                    .font(.kawaii(16, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .roundedCard()
    }

    private func options(_ word: WordEntry) -> some View {
        VStack(spacing: 12) {
            ForEach(store.options, id: \.self) { option in
                Button { store.send(.chose(option)) } label: {
                    HStack {
                        Text(option)
                            .font(.kawaii(22, weight: .bold)).foregroundStyle(optionText(option, word))
                        Spacer()
                        if store.answered, option == word.reading {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                        } else if store.answered, option == store.chosen {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.pink)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(optionFill(option, word))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(optionStroke(option, word), lineWidth: 2))
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
        VStack(spacing: 12) {
            ZStack {
                Sparkles()
                Text("🎉").font(.system(size: 52)).celebrate()
            }
            .frame(height: 80)
            Text(L.quizDone[appLanguage]).font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text("\(store.correctCount) / \(store.total)")
                .font(.kawaii(30, weight: .bold)).monospacedDigit().foregroundStyle(Palette.mint)
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
            Text("🍡").font(.system(size: 44))
            Text(L.quizEmpty[appLanguage]).font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .roundedCard().padding(16)
    }

    // Option styling: neutral until answered, then green (correct) / red (chosen wrong).
    private func optionText(_ option: String, _ word: WordEntry) -> Color {
        guard store.answered else { return Palette.ink }
        if option == word.reading { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Palette.inkSoft
    }
    private func optionFill(_ option: String, _ word: WordEntry) -> Color {
        guard store.answered else { return Palette.card }
        if option == word.reading { return Palette.mintSoft }
        if option == store.chosen { return Palette.pinkSoft }
        return Palette.card
    }
    private func optionStroke(_ option: String, _ word: WordEntry) -> Color {
        guard store.answered else { return Palette.ink.opacity(0.08) }
        if option == word.reading { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Color.clear
    }
}

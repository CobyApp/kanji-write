import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

/// The 칸켄 문제 허브 screen: a hub listing the 漢検 exam sections (읽기 / 부수 /
/// 쓰기) plus the 오답노트, and — once a section is picked — a mastery-loop
/// question player mirroring the study quiz look.
public struct KankenExamView: View {
    @Bindable public var store: StoreOf<KankenExamFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: StoreOf<KankenExamFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            AuroraBackground()
            if store.isPlaying {
                player
            } else {
                hub
            }
        }
        .task { store.send(.onAppear(level: store.level, language: appLanguage)) }
    }

    // MARK: - Hub

    private var hub: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                ForEach(KankenQuestionType.allCases, id: \.self) { type in
                    sectionCard(type)
                }
                wrongNoteCard
            }
            .padding(16)
            .readableWidth(sizeClass)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(L.kankenHub[appLanguage])
                .font(.kawaii(24, weight: .bold)).foregroundStyle(Palette.ink)
            Text("\(store.level) · \(L.kankenHubSubtitle[appLanguage])")
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 4)
    }

    private func sectionCard(_ type: KankenQuestionType) -> some View {
        Button { store.send(.selectType(type)) } label: {
            HStack(spacing: 14) {
                Text(type.numeral)
                    .font(.kawaiiJP(22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.jaTitle)
                        .font(.kawaiiJP(18, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    Text(sectionDesc(type))
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }

    private var wrongNoteCard: some View {
        Button { store.send(.selectWrongNote) } label: {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.wrongNote[appLanguage])
                        .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(L.wrongNoteDesc[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
                if store.wrongCount > 0 {
                    Text("\(store.wrongCount)")
                        .font(.kawaii(14, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.pink).clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
        .disabled(store.wrongCount == 0)
        .opacity(store.wrongCount == 0 ? 0.5 : 1)
    }

    private func sectionDesc(_ type: KankenQuestionType) -> String {
        switch type {
        case .reading: L.kankenReadingDesc[appLanguage]
        case .radical: L.kankenRadicalDesc[appLanguage]
        case .writing: L.kankenWritingDesc[appLanguage]
        }
    }

    // MARK: - Player

    @ViewBuilder
    private var player: some View {
        VStack(spacing: 0) {
            playerHeader
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
                .scrollIndicators(.hidden)
            } else if !store.isLoading {
                emptyCard
            }
        }
    }

    private var playerHeader: some View {
        HStack(spacing: 10) {
            Button { store.send(.exitToHub) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    Text(L.backToHub[appLanguage]).font(.kawaii(15, weight: .bold))
                }
                .foregroundStyle(Palette.inkSoft)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(store.sessionTitle)
                .font(.kawaiiJP(16, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
            Spacer()
            // Balances the back button so the title stays centered.
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .readableWidth(sizeClass)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("\(store.mastered) / \(store.total)")
                .font(.kawaii(15, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    private func questionCard(_ item: KankenQuestion) -> some View {
        VStack(spacing: 10) {
            Text(promptLabel(item.type))
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            promptText(item)
                .font(.kawaiiJP(promptSize(item.prompt), weight: .bold)).japaneseGlyphs()
                .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .roundedCard()
    }

    private func promptText(_ item: KankenQuestion) -> Text {
        guard let focus = item.focus, !focus.isEmpty,
              let range = item.prompt.range(of: focus) else { return Text(item.prompt) }
        let before = String(item.prompt[..<range.lowerBound])
        let target = String(item.prompt[range])
        let after = String(item.prompt[range.upperBound...])
        return Text(before)
            + Text(target).underline().foregroundColor(Palette.pink)
            + Text(after)
    }

    private func promptSize(_ prompt: String) -> CGFloat {
        switch prompt.count { case 0...3: 44; case 4...10: 30; default: 22 }
    }

    private func promptLabel(_ type: KankenQuestionType) -> String {
        switch type {
        case .reading: L.kankenReadingDesc[appLanguage]
        case .radical: L.kankenRadicalDesc[appLanguage]
        case .writing: L.kankenWritingDesc[appLanguage]
        }
    }

    private func options(_ item: KankenQuestion) -> some View {
        VStack(spacing: 12) {
            ForEach(item.options, id: \.self) { option in
                Button { store.send(.chose(option)) } label: {
                    HStack {
                        Text(option)
                            .font(.kawaiiJP(item.type == .reading ? 22 : 20, weight: .bold)).japaneseGlyphs()
                            .foregroundStyle(optionText(option, item)).multilineTextAlignment(.leading)
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

    @ViewBuilder
    private func explanationCard(_ item: KankenQuestion) -> some View {
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
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Palette.mint)
            Text(store.isWrongNote ? L.wrongNoteCleared[appLanguage] : L.quizDone[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { store.send(.restart) } label: {
                    Text(L.quizAgain[appLanguage])
                        .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Palette.accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { store.send(.exitToHub) } label: {
                    Text(L.backToHub[appLanguage])
                        .font(.kawaii(16, weight: .bold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Palette.card).clipShape(Capsule())
                        .overlay(Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard().padding(16)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: store.isWrongNote ? "checkmark.seal.fill" : "tray")
                .font(.system(size: 44)).foregroundStyle(store.isWrongNote ? Palette.mint : Palette.inkSoft)
            Text(store.isWrongNote ? L.wrongNoteEmpty[appLanguage] : L.kankenSectionEmpty[appLanguage])
                .font(.kawaii(16)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .roundedCard().padding(16)
    }

    // Option styling: neutral until answered, then green (correct) / red (chosen wrong).
    private func optionText(_ option: String, _ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.ink }
        if option == item.answer { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Palette.inkSoft
    }
    private func optionFill(_ option: String, _ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.card }
        if option == item.answer { return Palette.mintSoft }
        if option == store.chosen { return Palette.pinkSoft }
        return Palette.card
    }
    private func optionStroke(_ option: String, _ item: KankenQuestion) -> Color {
        guard store.answered else { return Palette.ink.opacity(0.08) }
        if option == item.answer { return Palette.mint }
        if option == store.chosen { return Palette.pink }
        return Color.clear
    }
}

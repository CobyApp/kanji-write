import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import WritingCanvas

/// The 칸켄 문제 허브 screen: a hub listing the 漢検 exam sections (읽기 / 부수 /
/// 쓰기) plus the 오답노트, and — once a section is picked — a mastery-loop
/// question player mirroring the study quiz look.
public struct KankenExamView: View {
    @Bindable public var store: StoreOf<KankenExamFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// How many questions the mock paper draws from each 大問.
    @State private var perSection = 5

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
                mockExamCard
                ForEach(examType.sections(for: store.level)) { section in
                    sectionCard(section)
                }
                wrongNoteCard
            }
            .padding(16)
            .readableWidth(sizeClass)
        }
        .scrollIndicators(.hidden)
    }

    /// "JLPT 문제" / "칸켄 문제", per the active exam.
    private var hubTitle: String {
        examType == .kanken ? L.kankenHub[appLanguage] : L.jlptHub[appLanguage]
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(hubTitle)
                .font(.kawaii(24, weight: .bold)).foregroundStyle(Palette.ink)
            Text("\(store.level) · \(L.kankenHubSubtitle[appLanguage])")
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 4)
    }

    @ViewBuilder
    private func sectionCard(_ section: ExamSection) -> some View {
        Button { if section.available { store.send(.selectSection(section)) } } label: {
            HStack(spacing: 14) {
                Text(section.numeral)
                    .font(.kawaiiJP(20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(section.available ? Palette.accent : Palette.inkSoft.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.jaTitle)
                        .font(.kawaiiJP(18, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    Text(section.available ? sectionDesc(section) : L.kankenComingSoon[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
                if section.available {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                } else {
                    Text(L.kankenComingSoon[appLanguage])
                        .font(.kawaii(11, weight: .bold)).foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.inkSoft.opacity(0.12)).clipShape(Capsule())
                }
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
        .disabled(!section.available)
        .opacity(section.available ? 1 : 0.6)
    }

    /// A full paper: every playable 大問 at this level, back to back. Sitting the
    /// whole thing is a different exercise from drilling one section, which is
    /// why it leads the hub rather than being buried at the end.
    private var mockExamCard: some View {
        let playable = examType.sections(for: store.level).filter(\.available).count
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.lavender)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.mockExam[appLanguage])
                        .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
                    Text(L.mockExamSub[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
                Text("\(playable)")
                    .font(.kawaii(14, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.lavender).clipShape(Capsule())
            }

            // How long a sitting: the total is this times the playable sections,
            // so it is shown rather than left to be worked out.
            VStack(spacing: 6) {
                HStack {
                    Text(L.mockExamSize[appLanguage])
                        .font(.kawaii(12, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text("\(perSection * playable)\(L.unitQuestions[appLanguage])")
                        .font(.kawaii(13, weight: .bold)).foregroundStyle(Palette.lavender)
                }
                Picker("", selection: $perSection) {
                    ForEach([3, 5, 10], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Button { store.send(.selectMockExam(perSection: perSection)) } label: {
                Text(L.mockExamStart[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(LinearGradient(colors: [Palette.lavender, Palette.sky],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.bouncy)
            .disabled(playable == 0)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.06), radius: 8, y: 3)
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

    /// A section's blurb. Keyed by the section, because ten 大問 share the
    /// `.writing` render type and would otherwise all claim to be 書き取り.
    private func sectionDesc(_ section: ExamSection) -> String {
        switch section.id {
        case "kousei": return L.kankenKouseiDesc[appLanguage]
        case "goji": return L.kankenGojiDesc[appLanguage]
        case "shikibetsu": return L.kankenShikibetsuDesc[appLanguage]
        case "common-kanji": return L.kankenKyotsuDesc[appLanguage]
        case "sanji": return L.kankenSanjiDesc[appLanguage]
        case "doonkun": return L.kankenDoonDesc[appLanguage]
        case "tsukuri": return L.kankenTsukuriDesc[appLanguage]
        case "word-selection": return L.kankenGoselectDesc[appLanguage]
        case "koji-kotowaza": return L.kankenKotowazaDesc[appLanguage]
        case "hyogai-reading": return L.kankenHyogaiDesc[appLanguage]
        case "jukujikun-ateji": return L.kankenJukujikunDesc[appLanguage]
        case "gokeisei": return L.kankenGokeiseiDesc[appLanguage]
        case "iikae": return L.kankenIikaeDesc[appLanguage]
        case "hantai", "taigi": return L.kankenHantaiDesc[appLanguage]
        default: return sectionDesc(section.renderType)
        }
    }

    private func sectionDesc(_ type: KankenQuestionType) -> String {
        switch type {
        case .reading: L.kankenReadingDesc[appLanguage]
        case .radical: L.kankenRadicalDesc[appLanguage]
        case .writing: L.kankenWritingDesc[appLanguage]
        case .context: L.kankenContextDesc[appLanguage]
        case .strokes: L.kankenStrokesDesc[appLanguage]
        case .yojijukugo: L.kankenYojiDesc[appLanguage]
        case .okurigana: L.kankenOkuriDesc[appLanguage]
        case .taigirui: L.kankenTaigiruiDesc[appLanguage]
        case .onkun: L.kankenOnKunDesc[appLanguage]
        case .hitsujun: L.kankenHitsujunDesc[appLanguage]
        case .comingSoon: L.kankenComingSoon[appLanguage]
        }
    }

    // MARK: - Player

    @ViewBuilder
    private var player: some View {
        VStack(spacing: 0) {
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

    /// The one top strip during a section: the section title and the progress
    /// count. Exiting is handled by the session's ✕ (top-left), so there's no
    /// separate back control here.
    private var progress: some View {
        HStack(spacing: 10) {
            Text(store.sessionTitle)
                .font(.kawaiiJP(15, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text("\(store.mastered) / \(store.total)")
                .font(.kawaii(15, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    private func questionCard(_ item: KankenQuestion) -> some View {
        VStack(spacing: 10) {
            Text(item.label ?? promptLabel(item.type))
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            if let paths = item.strokePaths, let marked = item.markedStroke {
                // 筆順 cannot be asked in text: the question is "this stroke,
                // where does it come?", so the stroke has to be pointed at.
                MarkedStrokeGlyph(paths: paths, marked: marked)
                    .frame(width: 180, height: 180)
            } else {
                promptText(item)
                    .font(.kawaiiJP(promptSize(item.prompt), weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        case .context: L.kankenContextDesc[appLanguage]
        case .strokes: L.kankenStrokesDesc[appLanguage]
        case .yojijukugo: L.kankenYojiDesc[appLanguage]
        case .okurigana: L.kankenOkuriDesc[appLanguage]
        case .taigirui: L.kankenTaigiruiDesc[appLanguage]
        case .onkun: L.kankenOnKunDesc[appLanguage]
        case .hitsujun: L.kankenHitsujunDesc[appLanguage]
        case .comingSoon: ""
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
        VStack(spacing: 14) {
            Image(systemName: store.isWrongNote ? "checkmark.seal.fill" : "tray")
                .font(.system(size: 44)).foregroundStyle(store.isWrongNote ? Palette.mint : Palette.inkSoft)
            Text(store.isWrongNote ? L.wrongNoteEmpty[appLanguage] : L.kankenSectionEmpty[appLanguage])
                .font(.kawaii(16)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
            Button { store.send(.exitToHub) } label: {
                Text(L.backToHub[appLanguage])
                    .font(.kawaii(15, weight: .bold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Palette.card).clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
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

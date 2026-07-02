import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI

/// The 単語 tab: the wordbook + its own FSRS review, separate from kanji.
/// A 復習 section (words whose review is due, self-graded) and the full 単語帳
/// list (every saved word, tappable to its detail).
public struct WordReviewHubView: View {
    @Bindable var wordStore: StoreOf<WordReviewFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(wordStore: StoreOf<WordReviewFeature>) {
        self.wordStore = wordStore
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if wordStore.savedIDs.isEmpty {
                        emptyCard
                    } else {
                        summaryCard
                        if !wordStore.dueIDs.isEmpty {
                            gradeSection
                        }
                        wordbookSection
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(L.words[appLanguage])
        .task { wordStore.send(.onAppear) }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("📖").font(.system(size: 44))
            Text(L.wordbookEmpty[appLanguage]).font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.wordbookEmptyHint[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.todayWords[appLanguage], accent: Palette.mint)
            HStack(spacing: 12) {
                stat(L.review[appLanguage], wordStore.dueIDs.count, Palette.lavender)
                stat(L.wordbook[appLanguage], wordStore.savedIDs.count, Palette.mint)
            }
        }
        .roundedCard()
    }

    private func stat(_ label: String, _ value: Int, _ accent: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.kawaii(26, weight: .bold)).foregroundStyle(accent)
            Text(label).font(.kawaii(12)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.review[appLanguage], accent: Palette.lavender)
            ForEach(wordStore.dueIDs, id: \.self) { id in
                if let word = wordStore.words[id: id] {
                    VStack(spacing: 10) {
                        wordRow(word, soft: Palette.lavenderSoft, accent: Palette.lavender)
                        HStack(spacing: 6) {
                            gradeButton(id, .again, L.gradeAgain[appLanguage], Palette.pink)
                            gradeButton(id, .hard, L.gradeHard[appLanguage], Palette.butter)
                            gradeButton(id, .good, L.gradeGood[appLanguage], Palette.mint)
                            gradeButton(id, .easy, L.gradeEasy[appLanguage], Palette.sky)
                        }
                    }
                }
            }
        }
        .roundedCard()
    }

    private var wordbookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.wordbook[appLanguage], accent: Palette.butter)
            ForEach(wordStore.savedIDs, id: \.self) { id in
                if let word = wordStore.words[id: id] {
                    Button { wordStore.send(.wordTapped(word)) } label: {
                        HStack {
                            wordRow(word, soft: Palette.butterSoft, accent: Palette.butter)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .roundedCard()
    }

    private func wordRow(_ word: WordEntry, soft: Color, accent: Color) -> some View {
        HStack(spacing: 12) {
            PastelTile(String(word.surface.prefix(1)), soft: soft, accent: accent,
                       size: 44, fontSize: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(word.surface)（\(word.reading)）")
                    .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.ink)
                if let meaning = meaning(word) {
                    Text(meaning).font(.kawaii(13, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gradeButton(_ id: Int, _ grade: Grade, _ label: String, _ color: Color) -> some View {
        Button { wordStore.send(.grade(wordID: id, grade: grade)) } label: {
            Text(label)
                .font(.kawaii(12, weight: .bold)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(color.opacity(0.16)).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func meaning(_ word: WordEntry) -> String? {
        switch appLanguage {
        case .ko: word.meaningKo ?? word.meaningEn
        case .ja: word.meaningJa ?? word.meaningEn
        case .zh: word.meaningZh ?? word.meaningEn
        case .en: word.meaningEn
        }
    }
}

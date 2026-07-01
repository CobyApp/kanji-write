import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI

/// The 学習 tab: an FSRS-driven daily session — due reviews + a capped number of
/// new kanji. Recall happens by tapping a card → detail → 書いて練習; the learner
/// then self-grades (Again/Hard/Good/Easy), which feeds the FSRS scheduler.
public struct StudyHubView: View {
    @Bindable var reviewStore: StoreOf<ReviewFeature>
    @AppStorage("newPerDay") private var newPerDay = 7

    public init(reviewStore: StoreOf<ReviewFeature>) {
        self.reviewStore = reviewStore
    }

    private var session: StudySession {
        todaysSession(
            records: reviewStore.records.elements,
            order: studyOrder(reviewStore.kanji.elements),
            today: reviewStore.today,
            newPerDay: newPerDay)
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                let session = session
                VStack(spacing: 16) {
                    summaryCard(session)
                    if !session.dueIDs.isEmpty {
                        gradeSection("復習", accent: Palette.lavender, soft: Palette.lavenderSoft,
                                     ids: session.dueIDs)
                    }
                    if !session.newIDs.isEmpty {
                        gradeSection("新規", accent: Palette.butter, soft: Palette.butterSoft,
                                     ids: session.newIDs)
                    }
                    if session.dueIDs.isEmpty && session.newIDs.isEmpty {
                        allDoneCard
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("学習")
        .task { reviewStore.send(.onAppear) }
    }

    private func summaryCard(_ session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("今日のセッション", accent: Palette.mint)
            HStack(spacing: 12) {
                stat("復習", session.dueIDs.count, Palette.lavender)
                stat("新規", session.newIDs.count, Palette.butter)
                stat("習得", reviewStore.records.count, Palette.mint)
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

    private var allDoneCard: some View {
        VStack(spacing: 10) {
            Text("🎉").font(.system(size: 44))
            Text("今日の学習は完了！").font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text("また明日ね").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .roundedCard()
    }

    private func gradeSection(_ title: String, accent: Color, soft: Color, ids: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title, accent: accent)
            ForEach(ids, id: \.self) { id in
                if let kanji = reviewStore.kanji[id: id] {
                    gradeRow(kanji, accent: accent, soft: soft)
                }
            }
        }
        .roundedCard()
    }

    private func gradeRow(_ kanji: Kanji, accent: Color, soft: Color) -> some View {
        VStack(spacing: 10) {
            Button { reviewStore.send(.kanjiTapped(kanji)) } label: {
                HStack(spacing: 14) {
                    PastelTile(kanji.literal, soft: soft, accent: accent, size: 50, fontSize: 28)
                    Text(kanji.onReadings.joined(separator: "、"))
                        .font(.kawaii(15)).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "pencil.tip").foregroundStyle(Palette.inkSoft)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                gradeButton(kanji.id, .again, "もう一度", Palette.pink)
                gradeButton(kanji.id, .hard, "むずい", Palette.butter)
                gradeButton(kanji.id, .good, "できた", Palette.mint)
                gradeButton(kanji.id, .easy, "かんたん", Palette.sky)
            }
        }
    }

    private func gradeButton(_ id: Int, _ grade: Grade, _ label: String, _ color: Color) -> some View {
        Button { reviewStore.send(.grade(kanjiID: id, grade: grade)) } label: {
            Text(label)
                .font(.kawaii(12, weight: .bold)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(color.opacity(0.16)).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

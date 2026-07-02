import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI

/// The 오늘/Home dashboard: today's plan summary and full-screen session launchers.
struct HomeView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var order: [Kanji] {
        studyOrder(store.review.kanji.elements, level: targetLevel)
    }
    private var remaining: Int { remainingNew(order: order, records: store.review.records.elements) }
    private var session: StudySession {
        todaysSession(records: store.review.records.elements, order: order,
                      today: store.review.today, newPerDay: newPerDay)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    planCard
                    startStudyButton
                    reviewButton
                    if sizeClass != .compact { practiceButton }
                    statsCard
                }
                .padding(16)
            }
        }
        .navigationTitle(L.today[appLanguage])
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.studyPlan[appLanguage], accent: Palette.mint)
            Text("\(targetLevel) · \(newPerDay)/\(L.daysUnit[appLanguage])")
                .font(.kawaii(20, weight: .bold)).foregroundStyle(Palette.ink)
            if remaining > 0 {
                Text("\(remaining) \(L.left[appLanguage]) · ~\(daysToFinish(remaining: remaining, perDay: newPerDay))\(L.daysUnit[appLanguage])")
                    .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
            } else {
                Text(L.levelDone[appLanguage]).font(.kawaii(14)).foregroundStyle(Palette.mint)
            }
        }
        .roundedCard()
    }

    private var startStudyButton: some View {
        Button { store.send(.startStudy) } label: {
            HStack {
                Image(systemName: "pencil.and.outline")
                Text(L.startStudy[appLanguage])
                Spacer()
                Text("\(session.newIDs.count)").monospacedDigit()
            }
            .font(.kawaii(18, weight: .bold)).foregroundStyle(.white)
            .padding(.vertical, 18).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var reviewButton: some View {
        let due = session.dueIDs.count
        return Button { store.send(.startReview) } label: {
            HStack {
                Image(systemName: "checkmark.circle")
                Text(L.review[appLanguage])
                Spacer()
                Text("\(due)").monospacedDigit()
            }
            .font(.kawaii(17, weight: .bold)).foregroundStyle(due > 0 ? Palette.lavender : Palette.inkSoft)
            .padding(.vertical, 16).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Palette.lavenderSoft.opacity(due > 0 ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(due == 0)
    }

    private var practiceButton: some View {
        Button { store.send(.startPractice) } label: {
            HStack {
                Image(systemName: "square.grid.3x3")
                Text(L.startPractice[appLanguage])
                Spacer()
            }
            .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.pink)
            .padding(.vertical, 16).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Palette.pinkSoft)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statsCard: some View {
        HStack(spacing: 12) {
            stat(L.learned[appLanguage], store.review.records.count, Palette.mint)
            stat(L.newItems[appLanguage], session.newIDs.count, Palette.butter)
        }
        .roundedCard()
    }

    private func stat(_ label: String, _ value: Int, _ accent: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.kawaii(24, weight: .bold)).foregroundStyle(accent)
            Text(label).font(.kawaii(12)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

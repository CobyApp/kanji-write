import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI

/// The 학습/Study hub: the plan summary and the three full-screen study-mode
/// launchers (learn / review / practice). Practice is iPad-only.
struct StudyHubView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var levelOrder: [Kanji] { studyOrder(store.review.kanji.elements, level: targetLevel) }
    private var remaining: Int { remainingNew(order: levelOrder, records: store.review.records.elements) }
    private var session: StudySession {
        todaysSession(records: store.review.records.elements, order: levelOrder,
                      today: store.review.today, newPerDay: newPerDay)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            FloatingBlobs()
            ScrollView {
                VStack(spacing: 20) {
                    planCard.popIn(delay: 0.02)
                    launcher(
                        emoji: "✏️", title: L.startStudy[appLanguage], subtitle: L.newKanjiSub[appLanguage],
                        count: session.newIDs.count, soft: Palette.pinkSoft, accent: Palette.pink,
                        action: { store.send(.startStudy) }
                    ).popIn(delay: 0.10)
                    reviewLauncher.popIn(delay: 0.18)
                    if sizeClass != .compact {
                        launcher(
                            emoji: "🖌️", title: L.startPractice[appLanguage], subtitle: L.practiceSub[appLanguage],
                            count: nil, soft: Palette.mintSoft, accent: Palette.mint,
                            action: { store.send(.startPractice) }
                        ).popIn(delay: 0.26)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L.study[appLanguage])
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.studyPlan[appLanguage], accent: Palette.mint)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(targetLevel).font(.kawaii(30, weight: .bold)).foregroundStyle(Palette.ink)
                Text("· \(newPerDay)/\(L.daysUnit[appLanguage])")
                    .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.inkSoft)
                Spacer()
            }
            if remaining > 0 {
                HStack(spacing: 6) {
                    CandyChip("\(remaining) \(L.left[appLanguage])", soft: Palette.lavenderSoft, accent: Palette.lavender)
                    CandyChip("~\(daysToFinish(remaining: remaining, perDay: newPerDay))\(L.daysUnit[appLanguage])",
                              soft: Palette.skySoft, accent: Palette.sky)
                }
            } else {
                CandyChip(L.levelDone[appLanguage], soft: Palette.mintSoft, accent: Palette.mint)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.06), radius: 10, y: 4)
    }

    private var reviewLauncher: some View {
        let due = session.dueIDs.count
        return Button { store.send(.startReview) } label: {
            launcherBody(
                emoji: "🔁", title: L.review[appLanguage],
                subtitle: due > 0 ? L.reviewSub[appLanguage] : L.allCaughtUp[appLanguage],
                count: due, soft: Palette.lavenderSoft, accent: Palette.lavender,
                dimmed: due == 0)
        }
        .buttonStyle(.bouncy)
        .disabled(due == 0)
    }

    private func launcher(
        emoji: String, title: String, subtitle: String, count: Int?,
        soft: Color, accent: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            launcherBody(emoji: emoji, title: title, subtitle: subtitle,
                         count: count, soft: soft, accent: accent, dimmed: false)
        }
        .buttonStyle(.bouncy)
    }

    private func launcherBody(
        emoji: String, title: String, subtitle: String, count: Int?,
        soft: Color, accent: Color, dimmed: Bool
    ) -> some View {
        HStack(spacing: 16) {
            Text(emoji)
                .font(.system(size: 30))
                .frame(width: 62, height: 62)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.kawaii(20, weight: .bold, language: appLanguage))
                    .foregroundStyle(Palette.ink)
                Text(subtitle).font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.kawaii(24, weight: .bold)).monospacedDigit()
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(soft)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1.5))
        .opacity(dimmed ? 0.55 : 1)
    }
}

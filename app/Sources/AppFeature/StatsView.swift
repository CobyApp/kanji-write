import Charts
import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI
import TestMode

/// 학습 기록 — pushed from Home.
struct StatsView: View {
    @Bindable var store: StoreOf<StatsFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 16) {
                    summary
                    activityChart
                    readinessCard
                    levelCard
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            NavHeader(title: L.studyStats[appLanguage], onBack: { dismiss() })
                .background(Palette.background.opacity(0.001))
        }
        .task { store.send(.onAppear) }
    }

    // MARK: Summary

    private var summary: some View {
        let learned = store.records.count
        let answered = store.totalAnswered
        let accuracy = answered > 0 ? Double(store.totalCorrect) / Double(answered) : nil
        return HStack(spacing: 10) {
            tile(L.totalLearned[appLanguage], "\(learned)", Palette.pinkDeep)
            tile(L.totalAnswered[appLanguage], "\(answered)", Palette.lavenderDeep)
            tile(L.overallAccuracy[appLanguage],
                 accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", Palette.mintDeep)
        }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.kawaii(24, weight: .bold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title)
                .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Palette.ink.opacity(0.05), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Activity

    private var activityChart: some View {
        let days = store.recentDays
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.last14Days[appLanguage], accent: Palette.sky)
            Chart {
                ForEach(days) { point in
                    BarMark(x: .value("day", label(point.day)),
                            y: .value(L.questionsChart[appLanguage], point.answered))
                        .foregroundStyle(by: .value("kind", L.questionsChart[appLanguage]))
                        .position(by: .value("kind", L.questionsChart[appLanguage]))
                    BarMark(x: .value("day", label(point.day)),
                            y: .value(L.kanjiLearnedChart[appLanguage], point.learned))
                        .foregroundStyle(by: .value("kind", L.kanjiLearnedChart[appLanguage]))
                        .position(by: .value("kind", L.kanjiLearnedChart[appLanguage]))
                }
            }
            .chartForegroundStyleScale([
                L.questionsChart[appLanguage]: Palette.lavender,
                L.kanjiLearnedChart[appLanguage]: Palette.pink,
            ])
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel().font(.kawaii(9))
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 190)
            .overlay {
                if days.allSatisfy({ $0.answered == 0 && $0.learned == 0 }) {
                    Text(L.noActivityYet[appLanguage])
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .roundedCard()
    }

    /// "9/26" for a day number.
    private func label(_ day: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    // MARK: Readiness

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("\(L.readiness[appLanguage]) · \(store.level)", accent: Palette.coral)
            if let coverage = store.coverage {
                meter(L.coverage[appLanguage], ratio: coverage.ratio,
                      detail: "\(coverage.learned) / \(coverage.total)", good: coverage.ratio >= 0.9)
            }
            if let score = store.estimatedScore {
                meter(L.estimatedScore[appLanguage], ratio: score,
                      detail: "\(Int((score * 100).rounded()))% · \(store.exam.hasOfficialPassLine ? L.examPassLine[appLanguage] : L.examGuideLine[appLanguage]) \(Int((store.passRatio * 100).rounded()))%",
                      good: score >= store.passRatio, marker: store.passRatio)
            } else {
                Text(L.estimateNeedsData[appLanguage])
                    .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                ForEach(store.sectionScores) { score in
                    sectionRow(score)
                }
            }
        }
        .roundedCard()
    }

    private func sectionRow(_ score: StatsFeature.State.SectionScore) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(score.section.jaTitle)
                    .font(.kawaiiJP(14, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let name = score.section.localizedName(appLanguage) {
                    Text(name)
                        .font(.kawaii(10, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(width: 120, alignment: .leading)
            if let stat = score.stat, stat.attempts > 0 {
                ProgressView(value: stat.accuracy)
                    .tint(stat.accuracy >= store.passRatio ? Palette.mint : Palette.coral)
                Text("\(Int((stat.accuracy * 100).rounded()))%")
                    .font(.kawaii(13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(stat.accuracy >= store.passRatio ? Palette.mintDeep : Palette.coralDeep)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text(L.notTriedYet[appLanguage])
                    .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func meter(_ title: String, ratio: Double, detail: String, good: Bool,
                       marker: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.kawaii(14, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                Spacer()
                Text(detail)
                    .font(.kawaii(12, weight: .bold, language: appLanguage)).monospacedDigit()
                    .foregroundStyle(good ? Palette.mintDeep : Palette.coralDeep)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.08))
                    Capsule().fill(good ? Palette.mint : Palette.coral)
                        .frame(width: geo.size.width * min(max(ratio, 0), 1))
                    if let marker {
                        Rectangle().fill(Palette.ink.opacity(0.6))
                            .frame(width: 2, height: 14)
                            .offset(x: geo.size.width * marker - 1)
                    }
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Levels

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.byLevel[appLanguage], accent: Palette.teal)
            ForEach(store.levelProgress) { progress in
                HStack(spacing: 10) {
                    Text(progress.level)
                        .font(.kawaiiJP(14, weight: .bold)).japaneseGlyphs()
                        .foregroundStyle(progress.level == store.level ? Palette.accent : Palette.ink)
                        .frame(width: 52, alignment: .leading)
                    ProgressView(value: progress.ratio).tint(Palette.teal)
                    Text("\(progress.learned)/\(progress.total)")
                        .font(.kawaii(12)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                        .frame(width: 76, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .roundedCard()
    }
}

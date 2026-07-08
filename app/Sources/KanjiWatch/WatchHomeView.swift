import SharedModels
import SwiftUI

/// Compact watch dashboard: the next kanji + meaning, a level-progress ring, and
/// today's goal / streak. Self-styled (no shared UI framework) to stay light and
/// avoid iOS-only dependencies.
struct WatchHomeView: View {
    let snapshot: StudySnapshot

    private var lang: AppLanguage { AppLanguage(rawValue: snapshot.language) ?? .ko }
    private let pink = Color(red: 1.0, green: 0.5, blue: 0.71)
    private let mint = Color(red: 0.52, green: 0.88, blue: 0.75)
    private let butter = Color(red: 1.0, green: 0.83, blue: 0.43)

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(pink.opacity(0.25), lineWidth: 6)
                    Circle().trim(from: 0, to: snapshot.progress)
                        .stroke(pink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(snapshot.nextGlyph.isEmpty ? "🌸" : snapshot.nextGlyph)
                            .font(.system(size: 30, weight: .bold))
                        Text(snapshot.level).font(.system(size: 11, weight: .bold)).foregroundStyle(pink)
                    }
                }
                .frame(width: 96, height: 96)

                if !snapshot.nextMeaning.isEmpty {
                    Text(snapshot.nextMeaning)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center).lineLimit(2)
                }

                row(L.todayGoal[lang], "\(snapshot.doneToday)/\(snapshot.dailyGoal)", mint)
                row(L.streak[lang], "\(snapshot.streak)", butter)
                row(L.learned[lang], "\(snapshot.learned)/\(snapshot.total)", pink)
            }
            .padding(.vertical, 4)
        }
    }

    private func row(_ label: String, _ value: String, _ accent: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(accent)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

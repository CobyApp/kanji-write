import DesignSystem
import SharedModels
import SwiftUI
import WidgetKit

/// A home-screen widget showing today's study snapshot — the next kanji, level
/// progress, today's goal, and the streak — read from the shared App Group.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: StudySnapshot
}

struct KanjiProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: StudySnapshotStore.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: StudySnapshotStore.load() ?? .placeholder)
        // Refresh hourly; the app also reloads timelines whenever it writes.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

private struct KanjiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var lang: AppLanguage { AppLanguage(rawValue: entry.snapshot.language) ?? .ko }

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var s: StudySnapshot { entry.snapshot }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.level).font(.kawaii(14, weight: .bold)).foregroundStyle(Palette.pink)
                Spacer()
                Text("\(Int(s.progress * 100))%").font(.kawaii(14, weight: .bold))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
            Text(s.nextGlyph.isEmpty ? "🌸" : s.nextGlyph)
                .font(.kawaiiJP(52, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
            if !s.nextMeaning.isEmpty {
                Text(s.nextMeaning).font(.kawaii(13, language: lang))
                    .foregroundStyle(Palette.inkSoft).lineLimit(1).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            goalBar
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(s.nextGlyph.isEmpty ? "🌸" : s.nextGlyph)
                    .font(.kawaiiJP(64, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                if !s.nextMeaning.isEmpty {
                    Text(s.nextMeaning).font(.kawaii(13, language: lang))
                        .foregroundStyle(Palette.inkSoft).lineLimit(1)
                }
            }
            .frame(width: 110)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(s.level).font(.kawaii(16, weight: .bold)).foregroundStyle(Palette.pink)
                    Text("\(s.learned)/\(s.total)").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
                    Spacer()
                }
                stat(L.todayGoal[lang], "\(s.doneToday)/\(s.dailyGoal)", Palette.mint)
                stat(L.streak[lang], "\(s.streak)", Palette.butter)
                goalBar
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ accent: Color) -> some View {
        HStack {
            Text(label).font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(value).font(.kawaii(16, weight: .bold)).monospacedDigit().foregroundStyle(accent)
        }
    }

    private var goalBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.mintSoft)
                Capsule().fill(LinearGradient(colors: [Palette.mint, Palette.sky],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * s.goalFraction)
            }
        }
        .frame(height: 7)
    }
}

@main
struct KanjiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KanjiWidget()
    }
}

struct KanjiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KanjiWidget", provider: KanjiProvider()) { entry in
            KanjiWidgetView(entry: entry)
                .containerBackground(Palette.background, for: .widget)
                // Tapping the widget starts today's study, not just the app.
                .widgetURL(URL(string: "mykanji://study"))
        }
        // The widget gallery is drawn by the system before the app runs, so these
        // two cannot come from `L` like the rest of the chrome — they resolve
        // through the target's String Catalog against the device language.
        .configurationDisplayName("漢字")
        .description("今日学ぶ漢字と進捗")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

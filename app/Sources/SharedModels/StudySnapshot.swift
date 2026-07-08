import Foundation

/// A tiny, self-contained summary of today's study state — the only thing the
/// widget and the Watch app need to render. The main app writes it; extensions
/// read it (widget via the shared App Group, Watch via WatchConnectivity).
public struct StudySnapshot: Codable, Equatable, Sendable {
    public var level: String
    public var dailyGoal: Int
    public var doneToday: Int
    public var streak: Int
    public var remaining: Int
    public var learned: Int
    public var total: Int
    public var nextGlyph: String
    public var nextMeaning: String
    /// The app language (AppLanguage rawValue) so the widget/watch localize.
    public var language: String

    public init(
        level: String, dailyGoal: Int, doneToday: Int, streak: Int,
        remaining: Int, learned: Int, total: Int, nextGlyph: String, nextMeaning: String,
        language: String = "ko"
    ) {
        self.level = level
        self.dailyGoal = dailyGoal
        self.doneToday = doneToday
        self.streak = streak
        self.remaining = remaining
        self.learned = learned
        self.total = total
        self.nextGlyph = nextGlyph
        self.nextMeaning = nextMeaning
        self.language = language
    }

    /// Level progress 0…1.
    public var progress: Double { total > 0 ? Double(learned) / Double(total) : 0 }
    /// Today's goal progress 0…1.
    public var goalFraction: Double { dailyGoal > 0 ? min(Double(doneToday) / Double(dailyGoal), 1) : 0 }

    /// Sample content for widget galleries / previews.
    public static let placeholder = StudySnapshot(
        level: "N5", dailyGoal: 5, doneToday: 2, streak: 3,
        remaining: 60, learned: 19, total: 79, nextGlyph: "山", nextMeaning: "메 산")
}

/// Reads/writes the snapshot in the shared App Group so the widget can see what
/// the app last recorded.
public enum StudySnapshotStore {
    public static let appGroup = "group.com.cobyapp.kanjiwrite"
    private static let key = "studySnapshot"

    public static func save(_ snapshot: StudySnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load() -> StudySnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(StudySnapshot.self, from: data) else { return nil }
        return snapshot
    }
}

import ComposableArchitecture
import Foundation
import Review
import SharedModels

/// 학습 기록: daily activity, per-level progress, and how ready the learner is
/// for their target level (kanji covered + first-try accuracy by 大問).
@Reducer
public struct StatsFeature {
    @ObservableState
    public struct State: Equatable {
        public var exam: ExamType
        public var level: String
        public var kanji: [Kanji]
        public var records: [ReviewRecord]
        public var today: Int
        public var stats: [String: SectionStat] = [:]
        public var log: [Int: DayLog] = [:]

        public init(exam: ExamType, level: String, kanji: [Kanji], records: [ReviewRecord], today: Int) {
            self.exam = exam
            self.level = level
            self.kanji = kanji
            self.records = records
            self.today = today
        }

        public struct DayPoint: Equatable, Identifiable, Sendable {
            public var id: Int { day }
            public let day: Int
            public let learned: Int
            public let answered: Int
            public let correct: Int
        }

        /// The last 14 days, oldest first. A record whose only review is its
        /// first one was learned on `lastReviewedDay`.
        public var recentDays: [DayPoint] {
            var learned: [Int: Int] = [:]
            for record in records where record.reps <= 1 {
                learned[record.lastReviewedDay, default: 0] += 1
            }
            return (0..<14).reversed().map { back in
                let day = today - back
                let entry = log[day] ?? DayLog()
                return DayPoint(day: day, learned: learned[day] ?? 0,
                                answered: entry.answered, correct: entry.correct)
            }
        }

        public var totalAnswered: Int { log.values.reduce(0) { $0 + $1.answered } }
        public var totalCorrect: Int { log.values.reduce(0) { $0 + $1.correct } }

        public struct LevelProgress: Equatable, Identifiable, Sendable {
            public var id: String { level }
            public let level: String
            public let learned: Int
            public let total: Int
            public var ratio: Double { total > 0 ? Double(learned) / Double(total) : 0 }
        }

        public var levelProgress: [LevelProgress] {
            let known = Set(records.map(\.kanjiID))
            return exam.levels.map { level in
                let members = kanji.filter { $0.belongs(to: level, exam: exam) }
                return LevelProgress(level: level,
                                     learned: members.filter { known.contains($0.id) }.count,
                                     total: members.count)
            }
        }

        public var coverage: LevelProgress? { levelProgress.first { $0.level == level } }

        public struct SectionScore: Equatable, Identifiable, Sendable {
            public var id: String { section.id }
            public let section: ExamSection
            public let stat: SectionStat?
        }

        /// Every playable section at the target level with its accuracy,
        /// weakest first; untried sections last.
        public var sectionScores: [SectionScore] {
            exam.sections(for: level).filter(\.available)
                .map { SectionScore(section: $0, stat: stats[SectionStat.key(level: level, section: $0.id)]) }
                .sorted { a, b in
                    switch (a.stat, b.stat) {
                    case let (x?, y?): return x.accuracy < y.accuracy
                    case (.some, nil): return true
                    default: return false
                    }
                }
        }

        /// The average first-try accuracy over sections answered at least five
        /// times — a rough stand-in for the paper's score. nil until there is
        /// enough to go on.
        public var estimatedScore: Double? {
            let judged = sectionScores.compactMap(\.stat).filter { $0.attempts >= 5 }
            guard !judged.isEmpty else { return nil }
            return judged.map(\.accuracy).reduce(0, +) / Double(judged.count)
        }

        public var passRatio: Double { exam.passRatio(for: level) }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded(stats: [String: SectionStat], log: [Int: DayLog])
    }

    @Dependency(\.sectionStatsStore) var sectionStatsStore
    @Dependency(\.studyLogStore) var studyLogStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    async let stats = sectionStatsStore.load()
                    async let log = studyLogStore.load()
                    await send(.loaded(stats: await stats, log: await log))
                }
            case let .loaded(stats, log):
                state.stats = stats
                state.log = log
                return .none
            }
        }
    }
}

import ComposableArchitecture
import Foundation
import SharedModels

/// Persists per-section first-try accuracy (`SectionStat`, keyed
/// "<level>|<section id>") so the exam hub can show where the learner is weak.
@DependencyClient
public struct SectionStatsStore: Sendable {
    public var load: @Sendable () async -> [String: SectionStat] = { [:] }
    /// Adds results to the stored tallies in one serialized step and returns
    /// the new totals. `results` maps a stat key to (attempts, correct).
    public var record: @Sendable (_ results: [String: SectionStat]) async -> [String: SectionStat] = { _ in [:] }
}

private actor SectionStatsFile {
    let directory: URL
    let url: URL
    init(directory: URL, url: URL) {
        self.directory = directory
        self.url = url
    }

    func load() -> [String: SectionStat] {
        guard let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode([String: SectionStat].self, from: data)
        else { return [:] }
        return stats
    }

    func record(_ results: [String: SectionStat]) -> [String: SectionStat] {
        var stats = load()
        for (key, delta) in results {
            var stat = stats[key] ?? SectionStat()
            stat.attempts += delta.attempts
            stat.correct += delta.correct
            stat.lastDay = max(stat.lastDay, delta.lastDay)
            stats[key] = stat
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: url, options: .atomic)
        }
        return stats
    }
}

extension SectionStatsStore {
    public static func directory(_ directory: URL, file: String = "section_stats.json") -> SectionStatsStore {
        let stats = SectionStatsFile(directory: directory, url: directory.appending(path: file))
        return SectionStatsStore(
            load: { await stats.load() },
            record: { await stats.record($0) }
        )
    }
}

extension SectionStatsStore: DependencyKey {
    public static let liveValue = SectionStatsStore.directory(URL.applicationSupportDirectory)
}

extension SectionStatsStore: TestDependencyKey {
    /// Stats are a side record of every answer; tests of other behaviour
    /// shouldn't have to stub them, so the test value quietly does nothing.
    public static let testValue = SectionStatsStore(load: { [:] }, record: { _ in [:] })
}

extension DependencyValues {
    public var sectionStatsStore: SectionStatsStore {
        get { self[SectionStatsStore.self] }
        set { self[SectionStatsStore.self] = newValue }
    }
}

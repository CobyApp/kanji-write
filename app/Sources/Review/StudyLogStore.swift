import ComposableArchitecture
import Foundation
import SharedModels

/// Persists per-day answer counts (epoch day → `DayLog`) for the 학습 기록 screen.
/// Only first attempts are logged, so a drill's retries don't inflate the day.
@DependencyClient
public struct StudyLogStore: Sendable {
    public var load: @Sendable () async -> [Int: DayLog] = { [:] }
    public var record: @Sendable (_ day: Int, _ correct: Bool) async -> Void
}

private actor StudyLogFile {
    let directory: URL
    let url: URL
    init(directory: URL, url: URL) {
        self.directory = directory
        self.url = url
    }

    func load() -> [Int: DayLog] {
        guard let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode([Int: DayLog].self, from: data)
        else { return [:] }
        return log
    }

    func record(day: Int, correct: Bool) {
        var log = load()
        var entry = log[day] ?? DayLog()
        entry.answered += 1
        if correct { entry.correct += 1 }
        log[day] = entry
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(log) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension StudyLogStore {
    public static func directory(_ directory: URL, file: String = "study_log.json") -> StudyLogStore {
        let log = StudyLogFile(directory: directory, url: directory.appending(path: file))
        return StudyLogStore(
            load: { await log.load() },
            record: { await log.record(day: $0, correct: $1) }
        )
    }
}

extension StudyLogStore: DependencyKey {
    public static let liveValue = StudyLogStore.directory(URL.applicationSupportDirectory)
}

extension StudyLogStore: TestDependencyKey {
    /// A side record of every answer; tests of other behaviour needn't stub it.
    public static let testValue = StudyLogStore(load: { [:] }, record: { _, _ in })
}

extension DependencyValues {
    public var studyLogStore: StudyLogStore {
        get { self[StudyLogStore.self] }
        set { self[StudyLogStore.self] = newValue }
    }
}

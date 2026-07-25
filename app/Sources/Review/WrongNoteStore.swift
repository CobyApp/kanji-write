import ComposableArchitecture
import Foundation
import SharedModels

/// Persists 오답노트 (wrong-answer notebook) entries — 漢検 questions the learner
/// missed — so they can be re-solved later. Each entry stores the whole question,
/// so the notebook works offline without re-querying the DB. Keyed by question id
/// (re-missing the same question refreshes it, never duplicates).
@DependencyClient
public struct WrongNoteStore: Sendable {
    public var load: @Sendable () async -> [WrongNote] = { [] }
    public var save: @Sendable (_ notes: [WrongNote]) async -> Void
}

extension WrongNoteStore {
    public static func directory(_ directory: URL, file: String = "wrong_notes.json") -> WrongNoteStore {
        let url = directory.appending(path: file)
        return WrongNoteStore(
            load: {
                guard let data = try? Data(contentsOf: url),
                      let notes = try? JSONDecoder().decode([WrongNote].self, from: data)
                else { return [] }
                return notes
            },
            save: { notes in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(notes) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        )
    }
}

extension WrongNoteStore: DependencyKey {
    public static let liveValue = WrongNoteStore.directory(URL.applicationSupportDirectory)
}

extension WrongNoteStore: TestDependencyKey {
    public static let testValue = WrongNoteStore()
}

extension DependencyValues {
    public var wrongNoteStore: WrongNoteStore {
        get { self[WrongNoteStore.self] }
        set { self[WrongNoteStore.self] = newValue }
    }
}

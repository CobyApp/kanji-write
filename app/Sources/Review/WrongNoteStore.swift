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
    /// Load, transform and save as one step. Every miss and every cleared note
    /// goes through here: two quick taps used to start two load–append–save
    /// effects that raced, and whichever saved last dropped the other's note.
    public var update: @Sendable (
        _ transform: @Sendable ([WrongNote]) -> [WrongNote]
    ) async -> [WrongNote] = { _ in [] }
}

/// Serializes read-modify-write on the notebook file.
private actor WrongNoteFile {
    let directory: URL
    let url: URL
    init(directory: URL, url: URL) {
        self.directory = directory
        self.url = url
    }

    func load() -> [WrongNote] {
        guard let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode([WrongNote].self, from: data)
        else { return [] }
        return notes
    }

    func save(_ notes: [WrongNote]) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func update(_ transform: @Sendable ([WrongNote]) -> [WrongNote]) -> [WrongNote] {
        let notes = transform(load())
        save(notes)
        return notes
    }
}

extension WrongNoteStore {
    public static func directory(_ directory: URL, file: String = "wrong_notes.json") -> WrongNoteStore {
        let notebook = WrongNoteFile(directory: directory, url: directory.appending(path: file))
        return WrongNoteStore(
            load: { await notebook.load() },
            save: { await notebook.save($0) },
            update: { await notebook.update($0) }
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

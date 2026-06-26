import ComposableArchitecture
import Foundation

/// Persists a kanji's handwriting (`PKDrawing` data), keyed by kanji id.
@DependencyClient
public struct DrawingStore: Sendable {
    public var loadDrawing: @Sendable (_ kanjiID: Int) async -> Data?
    public var saveDrawing: @Sendable (_ kanjiID: Int, _ data: Data) async -> Void
}

extension DrawingStore {
    /// A store backed by one file per kanji under `directory`.
    public static func directory(_ directory: URL) -> DrawingStore {
        func fileURL(_ kanjiID: Int) -> URL {
            directory.appending(path: "\(kanjiID).drawing")
        }
        return DrawingStore(
            loadDrawing: { kanjiID in try? Data(contentsOf: fileURL(kanjiID)) },
            saveDrawing: { kanjiID, data in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                try? data.write(to: fileURL(kanjiID), options: .atomic)
            }
        )
    }
}

extension DrawingStore: DependencyKey {
    public static let liveValue = DrawingStore.directory(
        URL.applicationSupportDirectory.appending(path: "drawings"))
}

extension DrawingStore: TestDependencyKey {
    public static let testValue = DrawingStore()
}

extension DependencyValues {
    public var drawingStore: DrawingStore {
        get { self[DrawingStore.self] }
        set { self[DrawingStore.self] = newValue }
    }
}

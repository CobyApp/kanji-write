import SharedModels
import SwiftUI
import WatchConnectivity

/// The watchOS companion. It shows today's study snapshot — next kanji, level
/// progress, today's goal, streak — synced from the iPhone over
/// WatchConnectivity (the phone pushes an application context whenever its plan
/// or records change). The last snapshot is cached so the watch shows something
/// immediately on launch.
@main
struct KanjiWatchApp: App {
    @StateObject private var sync = WatchSync()

    var body: some Scene {
        WindowGroup {
            WatchHomeView(snapshot: sync.snapshot)
        }
    }
}

/// Receives snapshots from the paired iPhone and caches the latest.
final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot: StudySnapshot

    override init() {
        snapshot = WatchCache.load() ?? .placeholder
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        apply(context)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(userInfo)
    }

    private func apply(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(StudySnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.snapshot = snap
            WatchCache.save(snap)
        }
    }
}

/// Persists the last snapshot in the watch's own defaults.
enum WatchCache {
    private static let key = "studySnapshot"
    static func save(_ s: StudySnapshot) {
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func load() -> StudySnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(StudySnapshot.self, from: data) else { return nil }
        return s
    }
}

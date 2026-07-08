import SharedModels

// WatchConnectivity is unavailable on Mac Catalyst, so the whole phone→watch
// sync is compiled only for iOS/iPadOS. On Catalyst `PhoneWatchSync.send` is a
// no-op (see the fallback below).
#if !targetEnvironment(macCatalyst)
import WatchConnectivity

/// Pushes the latest study snapshot to the paired Apple Watch as the session's
/// application context (the watch always sees the most recent state).
final class PhoneWatchSync: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSync()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: StudySnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#else
/// Mac Catalyst stub — WatchConnectivity isn't available there.
enum PhoneWatchSync {
    static let shared = PhoneWatchSync.self
    static func send(_ snapshot: StudySnapshot) {}
}
#endif

import UIKit

/// Small runtime platform checks shared across features.
public enum Platform {
    /// True only on a real iPad — false on iPhone and on Mac (Mac Catalyst or an
    /// iPad app running on Apple Silicon). Used to gate Apple-Pencil activities
    /// (free-writing practice, the in-study writing card) to iPad only.
    public static var isPad: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .pad && !ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }
}

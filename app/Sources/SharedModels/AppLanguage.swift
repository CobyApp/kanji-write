/// The app's selected language; drives which gloss/translation is shown.
/// `rawValue` doubles as the `@AppStorage` value and the DB `lang` code.
public enum AppLanguage: String, CaseIterable, Sendable {
    case ko, ja, zh, en

    public var glossKey: String { rawValue }

    public var label: String {
        switch self {
        case .ko: "한국어"
        case .ja: "日本語"
        case .zh: "中文"
        case .en: "English"
        }
    }
}

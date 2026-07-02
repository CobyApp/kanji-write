/// The app's selected language; drives which gloss/translation is shown.
/// `rawValue` doubles as the `@AppStorage` value and the DB `lang` code.
public enum AppLanguage: String, CaseIterable, Sendable {
    case ko, ja, zh, en

    /// Order for the language picker: Japanese first (the language being learned),
    /// then Korean, Chinese, English. Distinct from `allCases` (declaration order)
    /// so the picker can be reordered without affecting other iteration.
    public static let displayOrder: [AppLanguage] = [.ja, .ko, .zh, .en]

    public var glossKey: String { rawValue }

    public var label: String {
        switch self {
        case .ko: "한국어"
        case .ja: "日本語"
        case .zh: "中文"
        case .en: "English"
        }
    }

    /// BCP-47 locale identifier used to drive `Locale` for UI-string localization.
    public var localeIdentifier: String {
        switch self {
        case .ko: "ko"
        case .ja: "ja"
        case .zh: "zh-Hans"
        case .en: "en"
        }
    }
}

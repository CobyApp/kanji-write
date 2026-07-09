/// The user-selectable font for Japanese text (kanji, words, sentences).
/// `rawValue` is the `@AppStorage("japaneseFont")` value. Korean / Chinese /
/// Latin faces are fixed; only Japanese is switchable.
public enum JapaneseFont: String, CaseIterable, Sendable, Identifiable {
    // Klee One is the default: a textbook face whose kanji forms match the
    // KanjiVG stroke-order guide, so displayed kanji and the traced kanji agree.
    case klee         // Klee One — textbook handwriting, matches the stroke guide
    case zenMaru      // Zen Maru Gothic — rounded gothic
    case yomogi       // Yomogi — soft handwriting
    case hachiMaruPop // Hachi Maru Pop — bubbly kawaii
    case mochiyPop    // Mochiy Pop One — bold pop

    /// The default face (matches the stroke-order guide).
    public static let `default`: JapaneseFont = .klee

    public var id: String { rawValue }

    /// Korean label shown in the settings picker.
    public var label: String {
        switch self {
        case .klee: "교과서체"
        case .zenMaru: "둥근 고딕"
        case .yomogi: "손글씨"
        case .hachiMaruPop: "몽글몽글"
        case .mochiyPop: "통통 팝"
        }
    }

    /// PostScript name of the regular face.
    public var regularPSName: String {
        switch self {
        case .zenMaru: "ZenMaruGothic-Regular"
        case .klee: "KleeOne-Regular"
        case .yomogi: "Yomogi-Regular"
        case .hachiMaruPop: "HachiMaruPop-Regular"
        case .mochiyPop: "MochiyPopOne-Regular"
        }
    }

    /// PostScript name of the bold face (only Zen Maru ships a bold; the cute
    /// faces are single-weight and reuse their regular).
    public var boldPSName: String {
        switch self {
        case .zenMaru: "ZenMaruGothic-Bold"
        default: regularPSName
        }
    }
}

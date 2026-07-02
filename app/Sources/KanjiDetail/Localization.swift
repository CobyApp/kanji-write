import SharedModels

/// The word meaning for the selected language, falling back to English when the
/// native gloss for that language is absent.
func wordMeaning(_ word: WordEntry, _ language: AppLanguage) -> String? {
    switch language {
    case .ko: return word.meaningKo ?? word.meaningEn
    case .ja: return word.meaningJa ?? word.meaningEn
    case .zh: return word.meaningZh ?? word.meaningEn
    case .en: return word.meaningEn
    }
}

/// The kanji gloss for the selected language, falling back deterministically.
/// Skips empty strings so a blank gloss doesn't render as an empty line.
func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return nil
}

/// A sentence translation for the selected language. In Japanese mode the
/// example is already Japanese, so we show no translation line (rather than
/// falling back to English). Other languages fall back deterministically.
func localizedTranslation(_ translations: [String: String], _ language: AppLanguage) -> String? {
    if language == .ja { return nil }
    for key in [language.glossKey, "ko", "zh", "en"] {
        if let value = translations[key], !value.isEmpty { return value }
    }
    return nil
}

import SharedModels

/// The kanji gloss for the selected language, falling back deterministically.
public func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key] { return value }
    }
    return nil
}

/// A sentence translation for the selected language, falling back deterministically.
public func localizedTranslation(_ translations: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ko", "ja", "zh"] {
        if let value = translations[key] { return value }
    }
    return nil
}

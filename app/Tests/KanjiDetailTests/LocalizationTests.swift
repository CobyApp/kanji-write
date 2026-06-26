import SharedModels
import XCTest

@testable import KanjiDetail

final class LocalizationTests: XCTestCase {
    func testAppLanguageGlossKeyAndLabel() {
        XCTAssertEqual(AppLanguage.ko.glossKey, "ko")
        XCTAssertEqual(AppLanguage.allCases.map(\.glossKey), ["ko", "ja", "zh", "en"])
        XCTAssertEqual(AppLanguage.ja.label, "日本語")
        XCTAssertEqual(AppLanguage(rawValue: "zh"), .zh)
    }

    func testLocalizedGlossPrefersSelectedThenFallsBack() {
        let glosses = ["ko": "메 산", "ja": "やま。", "zh": "山。", "en": "mountain"]
        XCTAssertEqual(localizedGloss(glosses, .zh), "山。")
        XCTAssertEqual(localizedGloss(glosses, .en), "mountain")
        // missing selected language → en → ja → ko fallback chain
        XCTAssertEqual(localizedGloss(["ja": "やま。", "ko": "메 산"], .zh), "やま。")
        XCTAssertNil(localizedGloss([:], .ko))
    }

    func testLocalizedTranslationFallbackChain() {
        let tr = ["en": "It is high.", "ko": "높다."]
        XCTAssertEqual(localizedTranslation(tr, .ko), "높다.")
        XCTAssertEqual(localizedTranslation(tr, .zh), "It is high.")  // selected absent → en
        XCTAssertEqual(localizedTranslation(["ja": "高い。"], .zh), "高い。")  // → ... → ja
        XCTAssertNil(localizedTranslation([:], .ja))
    }

    func testEmptyStringValuesAreSkipped() {
        // A blank gloss in the selected language falls through to the next non-empty.
        XCTAssertEqual(localizedGloss(["ko": "", "en": "mountain"], .ko), "mountain")
        XCTAssertEqual(localizedTranslation(["zh": "", "ko": "높다."], .zh), "높다.")
    }
}

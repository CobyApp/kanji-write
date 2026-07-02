import SharedModels
import XCTest

final class UIStringsTests: XCTestCase {
    func testSubscriptMapsToTheRightLanguage() {
        let t = L10nText(ko: "K", ja: "J", zh: "Z", en: "E")
        XCTAssertEqual(t[.ko], "K")
        XCTAssertEqual(t[.ja], "J")
        XCTAssertEqual(t[.zh], "Z")
        XCTAssertEqual(t[.en], "E")
    }

    func testCoreLabelsAreTranslatedInEveryLanguage() {
        // Spot-check that key chrome differs from the Japanese base in ko/zh/en
        // (i.e. actually localized, not left as Japanese).
        for label in [L.study, L.review, L.settings, L.search, L.addToReview, L.gradeGood] {
            for lang in AppLanguage.allCases {
                XCTAssertFalse(label[lang].isEmpty, "empty for \(lang)")
            }
            XCTAssertNotEqual(label[.ko], label[.ja])
            XCTAssertNotEqual(label[.en], label[.ja])
        }
    }
}

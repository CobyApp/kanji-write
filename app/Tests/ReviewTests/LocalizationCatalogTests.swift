import XCTest

@testable import Review

/// Round-trip test proving the Review String Catalog is wired into the module's
/// resource bundle and resolves translations for a ja base key.
///
/// `String(localized:locale:)`'s `locale` argument only affects formatting, not
/// which `.lproj` is chosen (that follows the process's preferred languages), so
/// to assert a specific translation deterministically we resolve the
/// language-specific bundle (`<lang>.lproj`) and look the key up there.
final class LocalizationCatalogTests: XCTestCase {
    private func localized(_ key: String, _ language: String) throws -> String {
        let lprojURL = try XCTUnwrap(
            Bundle.module.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in Review resource bundle"
        )
        let bundle = try XCTUnwrap(Bundle(url: lprojURL))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func testAgainKeyLocalizesToKorean() throws {
        XCTAssertEqual(try localized("もう一度", "ko"), "다시")
    }

    func testNothingToReviewLocalizesToEnglish() throws {
        XCTAssertEqual(try localized("今日の復習はありません", "en"), "Nothing to review today")
    }
}

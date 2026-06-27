import XCTest

@testable import WritingCanvas

/// Round-trip test proving the WritingCanvas String Catalog is wired into the
/// module's resource bundle and resolves translations for a ja base key.
///
/// `String(localized:locale:)`'s `locale` argument only affects formatting, not
/// which `.lproj` is chosen (that follows the process's preferred languages), so
/// to assert a specific translation deterministically we resolve the
/// language-specific bundle (`<lang>.lproj`) and look the key up there.
final class LocalizationCatalogTests: XCTestCase {
    private func localized(_ key: String, _ language: String) throws -> String {
        let lprojURL = try XCTUnwrap(
            Bundle.module.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in WritingCanvas resource bundle"
        )
        let bundle = try XCTUnwrap(Bundle(url: lprojURL))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func testClearKeyLocalizesToKorean() throws {
        XCTAssertEqual(try localized("消す", "ko"), "지우기")
    }

    func testPlayKeyLocalizesToSimplifiedChinese() throws {
        XCTAssertEqual(try localized("再生", "zh-Hans"), "播放")
    }
}

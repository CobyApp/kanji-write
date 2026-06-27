import XCTest

@testable import Reminders

final class RemindersLocalizationTests: XCTestCase {
    func testCatalogRoundTrip() {
        XCTAssertEqual(localized("時刻", "ko"), "시각")
    }
}

private func localized(_ key: String, _ lang: String) -> String? {
    guard let url = Bundle.module.url(forResource: lang, withExtension: "lproj"),
          let bundle = Bundle(url: url) else { return nil }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}

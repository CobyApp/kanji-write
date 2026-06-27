import XCTest

@testable import StudyPlan

final class StudyPlanLocalizationTests: XCTestCase {
    func testCatalogRoundTrip() {
        XCTAssertEqual(localized("進捗", "en"), "Progress")
    }
}

private func localized(_ key: String, _ lang: String) -> String? {
    guard let url = Bundle.module.url(forResource: lang, withExtension: "lproj"),
          let bundle = Bundle(url: url) else { return nil }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}

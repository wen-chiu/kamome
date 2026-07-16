import XCTest

/// Proves the String Catalog pipeline end to end: the compiled app bundle must
/// resolve the sample key in both zh-Hant (development language) and en.
final class LocalizationTests: XCTestCase {
    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func testSampleStringResolvesInDevelopmentLanguage() throws {
        XCTAssertEqual(try localizedValue("start_journey", locale: "zh-Hant"), "開始出發")
    }

    func testSampleStringResolvesInEnglish() throws {
        XCTAssertEqual(try localizedValue("start_journey", locale: "en"), "Start Journey")
    }

    func testLimitedPhotosStringsResolve() throws {
        XCTAssertEqual(try localizedValue("limited_photos_manage", locale: "zh-Hant"), "選取更多相片")
        XCTAssertEqual(try localizedValue("limited_photos_manage", locale: "en"), "Select More Photos")
        XCTAssertEqual(try localizedValue("route_photos_header", locale: "zh-Hant"), "沿途照片")
        XCTAssertEqual(try localizedValue("route_photos_header", locale: "en"), "Along the route")
    }
}

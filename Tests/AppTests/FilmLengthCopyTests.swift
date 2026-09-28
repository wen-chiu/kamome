@testable import Kamome
import XCTest

/// The export sheet's film-length copy (Chiu 2026-09-27), kept out of
/// `LocalizationTests` for its size budget; same bundle lookup.
final class FilmLengthCopyTests: XCTestCase {
    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// The film-length copy (Chiu 2026-09-27) exists in both languages, and
    /// every number it says arrives as an argument — the ceiling is
    /// `total_duration_max_s`, so a "90" or "1.5" typed into the copy would
    /// go on promising it after the config changed.
    func testTheFilmLengthCopyTakesItsNumbersAsArguments() throws {
        let keys = [
            "recap_length_header", "recap_length_short", "recap_length_standard",
            "recap_length_short_footer", "recap_length_standard_footer", "recap_length_over",
            "recap_film_length_estimate"
        ]
        for key in keys {
            for locale in ["en", "zh-Hant"] {
                let value = try localizedValue(key, locale: locale)
                XCTAssertNotEqual(value, key, "\(key) is missing in \(locale)")
                let words = ["%1$@", "%2$@", "%@"].reduce(value) { $0.replacingOccurrences(of: $1, with: "") }
                XCTAssertNil(words.rangeOfCharacter(from: .decimalDigits), "\(key) in \(locale) types a number: \(value)")
                XCTAssertFalse(words.contains("一分半") || words.contains("分半") || words.contains("五分鐘"),
                               "\(key) in \(locale) names the ceiling itself: \(value)")
            }
        }
        XCTAssertEqual(try localizedValue("recap_length_short", locale: "zh-Hant"), "精華")
    }
}

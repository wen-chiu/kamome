@testable import Kamome
import XCTest

/// **The recording's time carries its units** (#332, Chiu 2026-10-29). It was
/// hours:minutes with none, so a minute in it read "0:01" beside "1.4 km", as
/// if the clock had stalled at one second. App Review saw exactly that in the
/// demo video.
final class RecordingElapsedTextTests: XCTestCase {
    private func calendar(_ locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    func testAMinuteReadsAsAMinuteNotASecond() {
        let english = calendar("en_US")
        XCTAssertEqual(RecordingView.elapsedText(seconds: 60, calendar: english), "1 min")
        XCTAssertEqual(RecordingView.elapsedText(seconds: 12 * 60 + 30, calendar: english), "12 min")
        XCTAssertEqual(RecordingView.elapsedText(seconds: 3600 + 5 * 60, calendar: english), "1 hr, 5 min")
    }

    func testChineseCarriesItsOwnUnits() {
        let chinese = calendar("zh_Hant_TW")
        XCTAssertEqual(RecordingView.elapsedText(seconds: 60, calendar: chinese), "1分鐘")
        XCTAssertEqual(RecordingView.elapsedText(seconds: 3600 + 5 * 60, calendar: chinese), "1小時5分鐘")
    }

    /// A trip recorded across days keeps counting hours: the HUD has no room
    /// for days, and "1 day" would hide how long the trip has been running.
    func testHoursKeepCountingPastADay() {
        XCTAssertEqual(RecordingView.elapsedText(seconds: 26 * 3600 + 2 * 60, calendar: calendar("en_US")), "26 hr, 2 min")
    }

    /// The bug's own shape, whatever the locale: digits, a colon, two digits.
    func testNoValueReadsAsAClock() {
        for locale in ["en_US", "zh_Hant_TW"] {
            for seconds: TimeInterval in [0, 59, 60, 61 * 60, 3600, 36_000] {
                let text = RecordingView.elapsedText(seconds: seconds, calendar: calendar(locale))
                XCTAssertNil(text.range(of: #"^\d+:\d{2}$"#, options: .regularExpression), "\(locale) \(seconds) s reads \(text)")
                XCTAssertFalse(text.isEmpty, "\(locale) \(seconds) s")
            }
        }
    }
}

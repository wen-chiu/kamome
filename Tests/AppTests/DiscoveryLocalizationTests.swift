import XCTest

/// **The Journey Discovery beta's copy** — split out of `LocalizationTests`
/// because the two branches that grew that file side by side pushed it past the
/// 400-line and 250-line-body limits, and the beta is a separable feature
/// (ADR 2026-09-18 (b)). It reads the compiled app bundle the same way.
final class DiscoveryLocalizationTests: XCTestCase {
    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// **The Journey Discovery beta** (2026-09-17, a beta since 2026-09-18 (b)).
    /// Its title, its one button and the film button must resolve in both
    /// languages — and **the original home's title must not have moved**: the
    /// beta is an added feature, so it has its own key rather than borrowing
    /// S1's and renaming it.
    func testDiscoveryHomeStringsResolve() throws {
        XCTAssertEqual(try localizedValue("home_title", locale: "en"), "My Journeys", "S1's title is untouched")
        XCTAssertEqual(try localizedValue("home_title", locale: "zh-Hant"), "我的旅程", "S1's title is untouched")
        XCTAssertEqual(try localizedValue("discovery_title", locale: "en"), "Your Journeys")
        XCTAssertEqual(try localizedValue("discovery_title", locale: "zh-Hant"), "你的旅程")
        XCTAssertEqual(try localizedValue("welcome_find", locale: "en"), "Find my journeys")
        XCTAssertEqual(try localizedValue("welcome_find", locale: "zh-Hant"), "找出我的旅程")
        XCTAssertEqual(try localizedValue("make_film", locale: "en"), "Make this a Film")
        XCTAssertEqual(try localizedValue("make_film", locale: "zh-Hant"), "做成一部影片")

        // **The welcome card may not say less than what is sent** — the class of
        // understatement `testPrivacyNoticeDescribesTwoDifferentPayloads` guards.
        // The first version read "nothing is uploaded" while each journey's
        // coordinates went to Apple to be named. So the card must name Apple and
        // what it receives, and that overclaim may not come back.
        let privacyEN = try localizedValue("welcome_privacy", locale: "en")
        XCTAssertTrue(privacyEN.lowercased().contains("never leave"), "photos stay: \(privacyEN)")
        XCTAssertTrue(privacyEN.lowercased().contains("until you open"), "nothing saved first: \(privacyEN)")
        XCTAssertTrue(privacyEN.contains("Apple"), "the recipient is named: \(privacyEN)")
        XCTAssertTrue(privacyEN.lowercased().contains("coordinates"), "and what it receives: \(privacyEN)")
        // Chiu's §0 exception is scoped to stop points (ADR 2026-09-16, PR #72:
        // 「停留點一定只能送 apple 去問」), so the card says a *stop* is what is sent.
        XCTAssertTrue(privacyEN.lowercased().contains("stop"), "what is sent is a stop: \(privacyEN)")
        XCTAssertFalse(privacyEN.lowercased().contains("nothing is uploaded"), "the overclaim: \(privacyEN)")
        let privacyZH = try localizedValue("welcome_privacy", locale: "zh-Hant")
        XCTAssertTrue(privacyZH.contains("不會離開"), "photos stay: \(privacyZH)")
        XCTAssertTrue(privacyZH.contains("打開之前"), "nothing saved first: \(privacyZH)")
        XCTAssertTrue(privacyZH.contains("Apple"), "the recipient is named: \(privacyZH)")
        XCTAssertTrue(privacyZH.contains("座標"), "and what it receives: \(privacyZH)")
        XCTAssertTrue(privacyZH.contains("停留點"), "what is sent is a stop: \(privacyZH)")
        XCTAssertFalse(privacyZH.contains("不會上傳"), "the overclaim: \(privacyZH)")

        // Provenance on the card: the recorded chip exists beside the photos one,
        // and neither says "verified" (§3).
        for locale in ["en", "zh-Hant"] {
            let recorded = try localizedValue("provenance_recorded", locale: locale)
            XCTAssertFalse(recorded.lowercased().contains("verified"), recorded)
            XCTAssertNotEqual(recorded, try localizedValue("provenance_badge", locale: locale))
        }
        // English inflects the card's counts; the catalogue's plurals must resolve.
        XCTAssertEqual(String.localizedStringWithFormat(try localizedValue("journey_days", locale: "en"), 1), "1 day")
        XCTAssertEqual(String.localizedStringWithFormat(try localizedValue("journey_days", locale: "en"), 12), "12 days")
    }
}

@testable import Kamome
import XCTest

/// **About opens with the app and speaks plainly** (Chiu 2026-10-26, #293, #305;
/// ADR `2026-10-26-about-opens-with-the-app-and-speaks-plainly`). The screen used
/// to open on eight terrain licences, with no name, version or way to reach
/// anyone, and its first-run half said 中繼 and 金鑰 to people who had never
/// heard either word.
final class AboutTests: XCTestCase {
    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    // MARK: - The screen

    /// Name, icon and version → privacy → feedback, then rating → credits →
    /// licences. Diagnostics was not in Chiu's list; where it sits is
    /// `AboutSection`'s comment, and it may not split the decided order.
    func testTheSectionsFollowTheDecidedOrder() {
        XCTAssertEqual(AboutSection.allCases, [.app, .privacy, .support, .diagnostics, .credits, .licences])
    }

    /// The two destinations are Chiu's, word for word: the site's support page,
    /// and the App Store's write-a-review sheet for Kamome's Apple ID.
    func testFeedbackAndRatingGoWhereChiuSaid() {
        XCTAssertEqual(AboutView.support.absoluteString, "https://wen-chiu.github.io/kamome-site/support/")
        XCTAssertEqual(
            AboutView.writeReview.absoluteString,
            "https://apps.apple.com/app/id6813758768?action=write-review"
        )
    }

    /// Read from the bundle, so it is this build's: a version typed into the
    /// screen would be wrong by the next build. The icon is the one thing the
    /// bundle could lose without a compile error.
    func testTheHeaderIsThisBuild() throws {
        let identity = AppIdentity.main
        XCTAssertEqual(identity.name, "Kamome", "the home-screen name, which stays Kamome in both languages")
        XCTAssertEqual(identity.version, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertFalse(identity.build.isEmpty, "the build number every build stamps")
        XCTAssertNotNil(identity.icon, "the app icon did not reach the bundle under CFBundleIcons")

        XCTAssertTrue(identity.versionLine.contains(identity.version), identity.versionLine)
        XCTAssertTrue(identity.versionLine.contains(identity.build), identity.versionLine)
        XCTAssertFalse(identity.versionLine.contains("%"), "an unfilled specifier: \(identity.versionLine)")
    }

    /// Both languages fill both places, in their own order of words.
    func testTheVersionLineFormatsInBothLanguages() throws {
        for locale in ["en", "zh-Hant"] {
            let line = String(
                format: try localizedValue("about_version", locale: locale),
                locale: Locale(identifier: locale), "9.8.7", "654"
            )
            XCTAssertTrue(line.contains("9.8.7") && line.contains("654"), "[\(locale)] \(line)")
            XCTAssertFalse(line.contains("%"), "[\(locale)] an unfilled specifier: \(line)")
        }
    }

    // MARK: - The words

    /// **The first-run card speaks without insider words, and still says once
    /// that importing reaches a third party** (Chiu 2026-10-26, #293; ADR
    /// 2026-09-05 (b)). 中繼 and 金鑰 meant nothing to the first-time user who
    /// read them on 2026-10-10. Dropping them may not drop the disclosure.
    func testTheFirstRunCardSpeaksPlainlyAndStillNamesTheThirdParty() throws {
        let insider = try NSRegularExpression(pattern: #"\b(relay|key)\b|中繼|金鑰"#, options: .caseInsensitive)
        for locale in ["en", "zh-Hant"] {
            for key in ["privacy_intro", "privacy_hop_relay", "privacy_hop_direct", "first_run_where"] {
                let line = try localizedValue(key, locale: locale)
                XCTAssertNil(
                    insider.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                    "[\(locale)] \(key) is on the first-run card and uses an insider word: \(line)"
                )
            }
        }
        let english = try localizedValue("privacy_hop_relay", locale: "en").lowercased()
        XCTAssertTrue(english.contains("import"), "the card must say importing is what sends: \(english)")
        XCTAssertTrue(english.contains("third-party"), "the road service is a third party: \(english)")
        let chinese = try localizedValue("privacy_hop_relay", locale: "zh-Hant")
        XCTAssertTrue(chinese.contains("匯入"), "the card must say importing is what sends: \(chinese)")
        XCTAssertTrue(chinese.contains("第三方"), "the road service is a third party: \(chinese)")
    }

    /// **The card says the server keeps nothing** (Chiu 2026-10-28, PR #323).
    /// It agrees with `privacy_relay_detail`, which says the same at length.
    func testTheHopSentenceSaysTheServerKeepsNothing() throws {
        XCTAssertTrue(try localizedValue("privacy_hop_relay", locale: "en").contains("keeps none"))
        XCTAssertTrue(try localizedValue("privacy_hop_relay", locale: "zh-Hant").contains("不留存"))
        XCTAssertTrue(try localizedValue("privacy_relay_detail", locale: "en").lowercased().contains("no record"))
        XCTAssertTrue(try localizedValue("privacy_relay_detail", locale: "zh-Hant").contains("不保留"))
    }

    /// **The control sentence stops overclaiming** (#305). Since Footprints,
    /// choosing what to import is not the only thing that decides what leaves:
    /// opening Footprints asks Apple to name every journey it finds. The
    /// sentence has to say so, name Apple, and keep the album it promised.
    func testPrivacyControlSaysWhatFootprintsAsksApple() throws {
        let english = try localizedValue("privacy_control", locale: "en")
        XCTAssertTrue(english.contains("Footprints") && english.contains("Apple"), english)
        let chinese = try localizedValue("privacy_control", locale: "zh-Hant")
        XCTAssertTrue(chinese.contains("足跡") && chinese.contains("Apple"), chinese)
        // The tab's own name, so the sentence points at something on screen.
        XCTAssertTrue(english.contains(try localizedValue("home_segment_footprints", locale: "en")))
        XCTAssertTrue(chinese.contains(try localizedValue("home_segment_footprints", locale: "zh-Hant")))
    }
}

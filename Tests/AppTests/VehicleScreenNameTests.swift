@testable import Kamome
import KamomeExportEngine
import XCTest

/// **A vehicle chip speaks the screen's language** (2026-09-26). The pickers
/// looked names up by `languageCode` ("zh") against a manifest keyed "zh-Hant",
/// so a Traditional Chinese screen showed "Red car". Nothing failed: the lookup
/// falls back to English by design, which is exactly why it needs a test.
final class VehicleScreenNameTests: XCTestCase {
    /// Every localization the app ships, as the bundle names it — the keys
    /// `Bundle.preferredLocalizations` can hand the chip.
    private var shippedLocalizations: [String] {
        Bundle.main.localizations.filter { $0 != "Base" && $0 != "en" }
    }

    func testTheAppShipsTraditionalChineseUnderTheManifestsKey() {
        XCTAssertTrue(shippedLocalizations.contains("zh-Hant"),
                      "the bundle's localizations: \(Bundle.main.localizations)")
    }

    func testEverySelectableVehicleHasItsOwnNameInEveryShippedLanguage() {
        for language in shippedLocalizations {
            for subject in VehicleCatalog.selectableSubjects {
                XCTAssertNotEqual(
                    subject.screenName(localizations: [language]),
                    subject.screenName(localizations: ["en"]),
                    "\(subject.id) has no \(language) name — the chip would show English"
                )
            }
        }
    }

    func testTheChipUsesTheBundlesChoiceNotTheLanguageCode() throws {
        let subject = try XCTUnwrap(VehicleCatalog.selectableSubjects.first)
        XCTAssertEqual(subject.screenName(localizations: ["zh-Hant", "en"]),
                       subject.displayName(language: "zh-Hant"))
        XCTAssertEqual(subject.screenName(localizations: []), subject.displayName(language: "en"))
    }
}

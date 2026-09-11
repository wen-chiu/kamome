import XCTest

/// The export screen's copy, held to the promise ADR 2026-09-10 allows.
///
/// Split from `LocalizationTests` only for SwiftLint's file-length limit; the
/// rule is the same class as that file's routing and privacy-notice tests — a
/// promise the app cannot keep, in either language, is a defect.
final class RecapExportCopyTests: XCTestCase {
    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// **The export screen may promise the screen, never the app** (Chiu
    /// 2026-09-10, Phase 4 closeout step 2).
    ///
    /// `AVAssetWriter` cannot resume across process death, so an export does not
    /// survive leaving Kamome — `ExportLifecycleGuard` buys the seconds iOS
    /// grants for a switch and nothing more. What the copy may say is exactly:
    /// leave this screen, stay in the app, the screen stays on.
    ///
    /// This is the same class of rule as `testRoutingCopyPromisesARetryOnlyWhereKamomeIsAtFault`
    /// — a promise the app cannot keep, in either language, is a defect rather
    /// than a wording choice. Matched loosely on purpose: the wording is still
    /// Chiu's to rule on and the rule has to survive the rewording.
    func testTheExportCopyPromisesTheScreenAndNeverTheBackground() throws {
        let english = try localizedValue("recap_rendering_leave_note", locale: "en").lowercased()
        for overpromise in ["background", "close the app", "quit", "even if you leave kamome"] {
            XCTAssertFalse(
                english.contains(overpromise),
                "[en] the export cannot survive leaving the app: \(english)"
            )
        }
        // It must still make the narrower promise, or the back button reads as
        // "this throws your film away".
        XCTAssertTrue(english.contains("leave this screen"), english)
        XCTAssertTrue(english.contains("open"), "the app has to stay open, and it must say so: \(english)")

        let chinese = try localizedValue("recap_rendering_leave_note", locale: "zh-Hant")
        for overpromise in ["背景", "關閉卡摸咩", "關掉 App"] {
            XCTAssertFalse(
                chinese.contains(overpromise),
                "[zh-Hant] the export cannot survive leaving the app: \(chinese)"
            )
        }
        XCTAssertTrue(chinese.contains("離開"), chinese)
        XCTAssertTrue(chinese.contains("開著") || chinese.contains("開啟"), chinese)
    }

    /// One export at a time is a hard rule, so the refusal has to be a sentence
    /// in both languages rather than a disabled button.
    func testTheBusyExportRefusalIsExplainedInBothLanguages() throws {
        for locale in ["en", "zh-Hant"] {
            XCTAssertFalse(try localizedValue("recap_export_busy", locale: locale).isEmpty)
            XCTAssertFalse(try localizedValue("recap_export_busy_detail", locale: locale).isEmpty)
            XCTAssertFalse(try localizedValue("recap_back", locale: locale).isEmpty)
        }
        XCTAssertTrue(try localizedValue("recap_export_busy_detail", locale: "en").contains("one film at a time"))
        XCTAssertTrue(try localizedValue("recap_export_busy_detail", locale: "zh-Hant").contains("一次只"))
    }
}

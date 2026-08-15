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

    /// The load-bearing S5 copy: the toggle must read as photo-cards-only, and
    /// the end-card CTA must not promise a scan. The MVP film carries no QR
    /// (PD-4) — "Get this route" invited an interaction nothing could honor, so
    /// the CTA points at the one thing the viewer *can* do.
    func testRecapStringsResolve() throws {
        XCTAssertEqual(try localizedValue("recap_photos_toggle", locale: "zh-Hant"), "停留照片卡")
        XCTAssertEqual(try localizedValue("recap_photos_toggle", locale: "en"), "Stop photo cards")
        XCTAssertTrue(try localizedValue("recap_photos_note", locale: "en").contains("always appear"))
        XCTAssertTrue(try localizedValue("recap_photos_note", locale: "zh-Hant").contains("一律會顯示"))
        XCTAssertEqual(try localizedValue("recap_end_cta", locale: "en"), "Record your own journey")
        XCTAssertEqual(try localizedValue("recap_end_cta", locale: "zh-Hant"), "記錄你自己的旅程")
    }

    func testLimitedPhotosStringsResolve() throws {
        XCTAssertEqual(try localizedValue("limited_photos_manage", locale: "zh-Hant"), "選取更多相片")
        XCTAssertEqual(try localizedValue("limited_photos_manage", locale: "en"), "Select More Photos")
        XCTAssertEqual(try localizedValue("route_photos_header", locale: "zh-Hant"), "沿途照片")
        XCTAssertEqual(try localizedValue("route_photos_header", locale: "en"), "Along the route")
    }

    /// S1 import hero + sheet copy (Replay MVP §4.7/§5).
    func testImportStringsResolve() throws {
        XCTAssertEqual(try localizedValue("import_from_photos", locale: "zh-Hant"), "從相片匯入旅程")
        XCTAssertEqual(try localizedValue("import_from_photos", locale: "en"), "Import from photos")
        XCTAssertEqual(try localizedValue("import_start", locale: "zh-Hant"), "開始匯入")
        XCTAssertEqual(try localizedValue("import_start", locale: "en"), "Import")
        // The friendly error must never blame the user or imply a defect.
        XCTAssertTrue(try localizedValue("import_error_no_photos", locale: "en").contains("geotagged"))
    }

    /// Album import (2026-08-15). The footer carries a product warning, not
    /// decoration: an album is not necessarily one trip, and if it holds two
    /// journeys the film draws a straight line between them. The copy has to say
    /// so in both languages before the user imports.
    func testAlbumImportStringsResolve() throws {
        XCTAssertEqual(try localizedValue("import_source_album", locale: "zh-Hant"), "相簿")
        XCTAssertEqual(try localizedValue("import_source_album", locale: "en"), "Album")

        let footerEN = try localizedValue("import_albums_footer", locale: "en")
        XCTAssertTrue(footerEN.contains("one trip"), footerEN)
        XCTAssertTrue(footerEN.contains("straight line"), footerEN)
        XCTAssertTrue(try localizedValue("import_albums_footer", locale: "zh-Hant").contains("直線"))

        // Limited access must be explained rather than left as an empty list.
        let limitedEN = try localizedValue("limited_photos_albums_notice", locale: "en")
        XCTAssertTrue(limitedEN.contains("hidden"), limitedEN)
        XCTAssertFalse(try localizedValue("limited_photos_albums_notice", locale: "zh-Hant").isEmpty)
    }

    /// Honest provenance (§3/§6): imported trips read as reconstructed, and the
    /// copy must never claim the trip is recorded or "verified".
    func testProvenanceStringsResolve() throws {
        XCTAssertEqual(try localizedValue("provenance_badge", locale: "zh-Hant"), "相片重建")
        XCTAssertEqual(try localizedValue("provenance_badge", locale: "en"), "From photos")
        let noteEN = try localizedValue("provenance_note", locale: "en")
        XCTAssertTrue(noteEN.contains("reconstructed"))
        XCTAssertFalse(noteEN.lowercased().contains("verified"))
        XCTAssertTrue(try localizedValue("provenance_note", locale: "zh-Hant").contains("重建"))
    }
}

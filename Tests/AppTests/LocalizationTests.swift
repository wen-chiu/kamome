import KamomeConfig
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

    /// **The routing copy may only promise what Kamome controls** (Chiu
    /// 2026-08-15), and this asserts it in both languages at once.
    ///
    /// The time budget is ours, so that case — and only that case — offers a
    /// retry. The connection and rate-limit cases are someone else's failure:
    /// they state the situation and stop. The no-road case promises nothing
    /// because nothing is wrong; it is PD-1/PD-2 rendered as a sentence, and a
    /// well-meaning "try exporting again" bolted onto it would turn an honest
    /// account of the journey into a bug report.
    ///
    /// A retry promise appearing in one language and not the other is a defect,
    /// not a stylistic difference — which is exactly what a translation pass
    /// tends to introduce, and what a human reviewer reading one language at a
    /// time cannot see.
    func testRoutingCopyPromisesARetryOnlyWhereKamomeIsAtFault() throws {
        // Matched loosely on purpose: the copy will be reworded, and the rule
        // has to survive the rewording. Any phrasing that tells the user to
        // export again counts.
        func promisesRetry(_ key: String) throws -> (en: Bool, zh: Bool) {
            let english = try localizedValue(key, locale: "en").lowercased()
            let chinese = try localizedValue(key, locale: "zh-Hant")
            let en = english.contains("export again") || english.contains("try again")
            let zh = ["再輸出", "重新輸出", "再試", "重試"].contains { chinese.contains($0) }
            return (en, zh)
        }

        for key in ["recap_routing_unreachable_detail", "recap_routing_rate_limited_detail",
                    "recap_routing_no_road_detail"] {
            let promise = try promisesRetry(key)
            XCTAssertFalse(
                promise.en || promise.zh,
                "\(key) promises a retry Kamome cannot keep — that outcome is not ours to fix"
            )
        }

        // Ours, so it may promise — and must promise in both languages or neither.
        let budget = try promisesRetry("recap_routing_budget_detail")
        XCTAssertTrue(budget.en, "the budget case is Kamome's own limit and should offer the retry")
        XCTAssertEqual(
            budget.en, budget.zh,
            "a retry promise in one language and not the other is a defect, not a translation choice"
        )
    }

    /// The count belongs to the headline in every case, so a missing specifier
    /// would silently print a headline with no number in it.
    func testEveryRoutingHeadlineCarriesTheLegCount() throws {
        for key in ["recap_routing_unreachable", "recap_routing_rate_limited",
                    "recap_routing_budget", "recap_routing_no_road"] {
            for locale in ["en", "zh-Hant"] {
                let value = try localizedValue(key, locale: locale)
                XCTAssertTrue(value.contains("%1$d"), "\(key) [\(locale)] must name how many legs: \(value)")
            }
        }
    }

    /// **S2 — a licence condition, not copy** (`Docs/release-readiness.md`).
    /// Geoapify attribution is mandatory on the free plan in the format
    /// `Powered by Geoapify` with a link, and OpenStreetMap attribution is
    /// always required. The app shipped its whole life without either.
    ///
    /// The Geoapify line is asserted **identical in both languages on purpose**:
    /// the required thing is that format, so a well-meaning translation pass
    /// would break the obligation while looking like an improvement — which is
    /// exactly the failure `testRoutingCopyPromisesARetryOnlyWhereKamomeIsAtFault`
    /// was written for in the other direction.
    func testAttributionCarriesBothLicenceObligations() throws {
        for locale in ["en", "zh-Hant"] {
            XCTAssertEqual(
                try localizedValue("attribution_geoapify", locale: locale), "Powered by Geoapify",
                "[\(locale)] the free plan requires this exact format"
            )
            XCTAssertTrue(
                try localizedValue("attribution_osm", locale: locale).contains("OpenStreetMap"),
                "[\(locale)] OSM attribution is always required"
            )
        }
    }

    /// **S3 — the notice must describe two different payloads** (`pre-launch.md`,
    /// ADR 2026-08-20 (c)). The approved one-liner — "the start and end
    /// coordinates of each leg" — is untrue of both paths, and a notice that
    /// understates what is sent is worse than no notice.
    ///
    /// The imported sentence is held to naming **both** config quantities, which
    /// is the structural form of "more than a start and an end": a rewrite that
    /// collapses back to two coordinates cannot keep the specifiers.
    func testPrivacyNoticeDescribesTwoDifferentPayloads() throws {
        for locale in ["en", "zh-Hant"] {
            let imported = try localizedValue("privacy_imported_body", locale: locale)
            XCTAssertTrue(imported.contains("%1$"), "[\(locale)] the thinning distance must come from config")
            XCTAssertTrue(imported.contains("%2$"), "[\(locale)] the per-leg cap must come from config")
        }
        // Content, not just shape: photograph positions are the half the approved
        // wording left out, and they are why the payload is not two coordinates.
        XCTAssertTrue(try localizedValue("privacy_imported_body", locale: "en").contains("photographs"))
        XCTAssertTrue(try localizedValue("privacy_imported_body", locale: "zh-Hant").contains("相片"))
        XCTAssertFalse(
            try localizedValue("privacy_imported_body", locale: "en").lowercased().contains("start and end"),
            "the corrected wording may not come back"
        )

        // The recorded payload is a different sentence because it is a different
        // fact: no matcher is constructed on the shipped path, so nothing is sent.
        XCTAssertTrue(try localizedValue("privacy_recorded_body", locale: "en").contains("not sent"))
        XCTAssertTrue(try localizedValue("privacy_recorded_body", locale: "zh-Hant").contains("不會送到"))
    }

    /// **A notice may not promise a control the app does not offer** (ADR
    /// 2026-08-20 (c) §4). The album path is what `privacy_control` names, and it
    /// ships — `ImportSheet.albumSection`. If album import is ever removed, this
    /// test is the thing that says the notice became a false promise.
    ///
    /// Retention is asserted with its exception: Geoapify's ≤24 h sentence covers
    /// **successful** requests, and dropping the failures clause would overstate
    /// the guarantee in the user's favour, which is still a false statement.
    func testPrivacyNoticePromisesOnlyControlsTheAppOffers() throws {
        XCTAssertTrue(try localizedValue("privacy_control", locale: "en").lowercased().contains("album"))
        XCTAssertTrue(try localizedValue("privacy_control", locale: "zh-Hant").contains("相簿"))

        let retentionEN = try localizedValue("privacy_retention", locale: "en")
        XCTAssertTrue(retentionEN.contains("24 hours"), retentionEN)
        XCTAssertTrue(retentionEN.contains("fail"), "the failures exception must survive: \(retentionEN)")
        let retentionZH = try localizedValue("privacy_retention", locale: "zh-Hant")
        XCTAssertTrue(retentionZH.contains("24 小時"), retentionZH)
        XCTAssertTrue(retentionZH.contains("失敗"), "the failures exception must survive: \(retentionZH)")
    }

    /// The two specifiers must match the two arguments `AboutView` passes, or the
    /// notice renders a garbage number to the user while every other test above
    /// still passes. Formats the sentence exactly as the screen does, against the
    /// config the app actually ships.
    func testPrivacyImportedBodyRendersTheShippedConfigNumbers() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "TrackingConfig", withExtension: "json"))
        let matching = try TrackingConfigLoader.load(contentsOf: url).matching

        for locale in ["en", "zh-Hant"] {
            let rendered = String(
                format: try localizedValue("privacy_imported_body", locale: locale),
                locale: Locale(identifier: locale),
                matching.routeWaypointMinSpacingM, matching.chunkSize
            )
            XCTAssertTrue(rendered.contains("250"), "[\(locale)] thinning distance: \(rendered)")
            XCTAssertTrue(rendered.contains("100"), "[\(locale)] per-leg cap: \(rendered)")
            XCTAssertFalse(rendered.contains("%"), "[\(locale)] an unfilled specifier: \(rendered)")
        }
    }
}

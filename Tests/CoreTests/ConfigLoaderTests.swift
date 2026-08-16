import KamomeConfig
import XCTest

final class ConfigLoaderTests: XCTestCase {
    /// Repo-root Config/TrackingConfig.json, located relative to this source file
    /// so the test works in both `swift test` and xcodebuild runs.
    private var configURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/CoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Config/TrackingConfig.json")
    }

    /// The predicate behind the release guard in `AppConfig.loadOrDie`
    /// (2026-08-15). It reads the shipped block only to inherit every *other*
    /// tunable, then overrides the one value under test — so a working tree
    /// pointed at a dogfood server still runs this test green, which is the
    /// behaviour the guard is designed around.
    func testOnlyEmptyOrHTTPSEndpointsMayShip() throws {
        let shipped = try TrackingConfigLoader.load(contentsOf: configURL).matching

        XCTAssertTrue(shipped.withBaseURL("").isDistributableEndpoint, "matching disabled must ship")
        XCTAssertTrue(shipped.withBaseURL("https://routing.example.com").isDistributableEndpoint)
        XCTAssertTrue(shipped.withBaseURL("HTTPS://routing.example.com").isDistributableEndpoint, "scheme is case-insensitive")

        XCTAssertFalse(shipped.withBaseURL("http://192.168.50.179:5100").isDistributableEndpoint, "the P0 shape")
        XCTAssertFalse(shipped.withBaseURL("http://127.0.0.1:5100").isDistributableEndpoint)
        XCTAssertFalse(shipped.withBaseURL("http://routing.example.com").isDistributableEndpoint)
        XCTAssertFalse(shipped.withBaseURL("192.168.50.179:5100").isDistributableEndpoint, "no scheme at all")
    }

    func testLoadsShippedConfigWithSpecDefaults() throws {
        let config = try TrackingConfigLoader.load(contentsOf: configURL)

        XCTAssertEqual(config.schemaVersion, 1)
        try assertTrackingDefaults(config)
        try assertExportDefaults(config)
    }

    /// Capture / matching / import tunables.
    private func assertTrackingDefaults(_ config: TrackingConfig) throws {
        // Defaults named in the spec (§2.3, §4.1, §4.2, §4.4, §4.5).
        XCTAssertEqual(config.segmentation.modeConfirmS, 60)
        XCTAssertEqual(config.segmentation.speedTransitMinKmh, 130)
        XCTAssertEqual(config.dwell.windowS, 180)
        XCTAssertEqual(config.dwell.radiusM, 80)
        XCTAssertEqual(config.dwell.regionRadiusM, 150)
        // Trip-end stop derivation (ADR 2026-07-18).
        XCTAssertEqual(config.dwell.gapMinS, 300)
        XCTAssertEqual(config.dwell.visitMinS, 300)
        XCTAssertEqual(config.dwell.visitReturnRadiusM, 300)
        XCTAssertEqual(config.simplify.epsilonM, 15)
        // Map matching (§4.4, P3.5): disabled until the OSRM server exists.
        XCTAssertEqual(config.matching.baseURL, "")
        XCTAssertEqual(config.matching.chunkSize, 100)
        XCTAssertEqual(config.matching.confidenceMin, 0.5)
        XCTAssertEqual(config.matching.radiusM, 25)
        XCTAssertEqual(config.matching.timeoutS, 10)
        // Per-trip routing ceiling (2026-08-15): `timeout_s` bounds a request,
        // this bounds the walk of legs behind it.
        XCTAssertEqual(config.matching.tripBudgetS, 60)
        XCTAssertEqual(config.matching.displayEpsilonM, 5)
        // Route reconstruction for sparse EXIF legs (typed-leg pass 2026-07-26).
        XCTAssertEqual(config.matching.routeMaxDetourRatio, 2.5)
        XCTAssertEqual(config.matching.routeWaypointMinSpacingM, 250)
        XCTAssertEqual(config.matching.routeWaypointRadiusM, 500)
        XCTAssertEqual(config.sampling.vehicles.car.fast.distanceFilterM, 50)
        XCTAssertEqual(config.sampling.vehicles.car.slow.distanceFilterM, 20)
        XCTAssertEqual(config.sampling.vehicles.car.fastMinKmh, 20)
        XCTAssertEqual(config.sampling.walk.distanceFilterM, 10)
        XCTAssertEqual(config.filter.maxHAccM, 50)
        XCTAssertEqual(config.filter.speedMaxHAccM, 25)
        // Phantom-trip guard (ADR 2026-07-16).
        XCTAssertEqual(config.trip.minDurationS, 60)
        XCTAssertEqual(config.trip.minDistanceM, 100)
        // Photo-EXIF import clustering (§4.7, Replay MVP) — prototype defaults.
        XCTAssertEqual(config.photoImport.stopRadiusM, 4000)
        XCTAssertEqual(config.photoImport.stopSplitGapS, 10_800)
        XCTAssertEqual(config.photoImport.minPhotosPerStop, 2)
        XCTAssertEqual(config.photoImport.deckMinPhotos, 3)
        XCTAssertEqual(config.photoImport.deckMaxPhotos, 8)
        XCTAssertEqual(config.photoImport.paceUnknowableGapS, 14_400)
        XCTAssertEqual(config.photoImport.defaultRangeDays, 7)
    }

    /// The §4.5 recap-export block: frame, pacing, prologue, duration window.
    private func assertExportDefaults(_ config: TrackingConfig) throws {
        XCTAssertEqual(config.export.targetDurationS, 30)
        XCTAssertEqual(config.export.maxHoldFraction, 0.6)
        // Frame render tunables (§4.5 step 2).
        XCTAssertEqual(config.export.frameWidthPx, 1080)
        XCTAssertEqual(config.export.frameHeightPx, 1920)
        XCTAssertEqual(config.export.cameraSpanM, 1500)
        // Follow-cam framing (§4.5 step 1, prototype §2.3).
        XCTAssertEqual(config.export.wideSpanPadding, 1.5)
        XCTAssertEqual(config.export.zoomTransitionS, 2.5)
        XCTAssertFalse(config.export.followHeadingUp)
        // Photo-deck pacing (§5, Chiu 2026-07-23).
        XCTAssertEqual(config.export.deckPhotoHoldS, 2.5)
        XCTAssertEqual(config.export.deckZoomS, 0.5)
        XCTAssertEqual(config.export.actSplitKm, 25)
        XCTAssertEqual(config.export.deckLabelLeadS, 0.6)
        // Cinematic pass (Chiu 2026-07-30): a one-time opening prologue, and a
        // film whose length follows its content instead of a flat 30 s.
        XCTAssertEqual(config.export.openingCountryS, 3.0)
        XCTAssertEqual(config.export.countryViewPadding, 2.2)
        XCTAssertEqual(config.export.firstStopDwellScale, 0.55)
        XCTAssertEqual(config.export.openingRegionalS, 1.0)
        XCTAssertEqual(config.export.stopDwellMinS, 6)
        XCTAssertEqual(config.export.stopDwellMaxS, 25)
        XCTAssertEqual(config.export.totalDurationMinS, 60)
        XCTAssertEqual(config.export.totalDurationMaxS, 90)
        XCTAssertEqual(config.export.keyframeIntervalFrames, 15)
        // The moving subject's canvas size (Phase 4). Was a hard-coded 300 in
        // RecapStyle — 28% of frame width, which users said was too big.
        XCTAssertEqual(config.export.subjectLengthPx, 250)
        XCTAssertEqual(config.export.titleCardS, 3.0)
        XCTAssertEqual(config.export.endCardS, 3.0)
        XCTAssertEqual(config.export.videoBitrateMbps, 5)
        // Earned stops — the one place trip size enters the duration model
        // (Chiu 2026-08-14). The cap is 21 and not 22 on purpose: it is the stop
        // count of the Iceland film that was watched and approved.
        XCTAssertEqual(config.export.earnedStopsFloor, 8)
        XCTAssertEqual(config.export.earnedStopsCap, 21)
        XCTAssertEqual(config.export.earnedStopsPerDoubling, 7)
        XCTAssertEqual(config.export.earnedStopsReferenceTripStops, 10)
    }

    func testMissingKeyFailsLoudlyNamingTheKey() throws {
        var json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL)
        ) as? [String: Any] ?? [:]
        var dwell = json["dwell"] as? [String: Any] ?? [:]
        dwell.removeValue(forKey: "radius_m")
        json["dwell"] = dwell
        let mutated = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try TrackingConfigLoader.load(from: mutated)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("dwell.radius_m"), "error should name the key, got: \(message)")
        }
    }

    func testGarbageInputFailsLoudly() {
        XCTAssertThrowsError(try TrackingConfigLoader.load(from: Data("not json".utf8)))
    }
}

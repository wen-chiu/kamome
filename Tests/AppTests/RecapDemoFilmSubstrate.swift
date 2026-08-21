@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import XCTest

/// **Which base map a review film draws on, which subject rides it, and the two
/// overrides that vary them** — split out of `RecapDemoFilmTests` so both files
/// stay inside the size limits, the same way `RecapDemoFilmAssets` and
/// `RecapTripFixtures` already are.
extension RecapDemoFilmTests {
    /// The subject under review, from `KAMOME_SUBJECT`.
    ///
    /// The same override `RecapReviewScene` has carried since the sprite sweeps.
    /// It is repeated here rather than shared because that scene cannot render
    /// at all without an installed MapLibre region, and this harness is the one
    /// that produces films today. Nothing touches the config file, so a choice
    /// made for one render can never be committed.
    static func subjectRenderer(
        style: RecapStyle, config: TrackingConfig.Export
    ) -> VehicleSubjectRenderer {
        let subjectId = HarnessEnv.value("KAMOME_SUBJECT")
        print("KAMOME_DEMO_FILM subject \(subjectId ?? VehicleCatalog.defaultSubjectId)")
        return VehicleSubjectRenderer.make(style: style, config: config, subjectId: subjectId)
    }

    /// The Apple Maps experiment, from `KAMOME_MAP_DISPLAY_SCALE` and
    /// `KAMOME_MAP_APPEARANCE` (2026-08-22).
    ///
    /// Both are review-only overrides for one question Chiu judges by looking —
    /// whether a dark base suits the film, and whether place labels drawn at a
    /// higher display scale are the right size. They are env rather than config
    /// keys precisely because nothing has been judged yet: a `TrackingConfig`
    /// entry would ship an answer to a question still open.
    ///
    /// An unparseable value is refused rather than quietly ignored. A review
    /// render that silently used a different setting than the reviewer asked for
    /// is worse than one that did not run.
    static func mapExperiment() throws -> (displayScale: Int, appearance: MapKitSnapshotProvider.Appearance) {
        var displayScale = 1
        if let raw = HarnessEnv.value("KAMOME_MAP_DISPLAY_SCALE") {
            guard let parsed = Int(raw), parsed >= 1 else {
                throw HarnessError("KAMOME_MAP_DISPLAY_SCALE=\(raw) is not a display scale (try 1, 2 or 3)")
            }
            displayScale = parsed
        }
        var appearance = MapKitSnapshotProvider.Appearance.light
        if let raw = HarnessEnv.value("KAMOME_MAP_APPEARANCE") {
            switch raw {
            case "light": appearance = .light
            case "dark": appearance = .dark
            default: throw HarnessError("KAMOME_MAP_APPEARANCE=\(raw) is not 'light' or 'dark'")
            }
        }
        return (displayScale, appearance)
    }

    /// The base map this render will use — **and falling back is not a failure**.
    ///
    /// This used to `XCTFail` when no `.pmtiles` region covered the trip, which
    /// made every successful run of the harness report a failure: since the
    /// 2026-08-08 substrate ADR Apple Maps *is* the shipping substrate and
    /// MapLibre is parked, so no region is the normal state, not a missing
    /// setting. Per Arch.md §7.3 the assertion is restated rather than deleted —
    /// the rule it now holds is `testAFilmRendersOnWhicheverSubstrateIsAvailable`
    /// below: a film always gets a substrate, and which one is *reported*, never
    /// judged.
    func snapshotProvider(region: RecapMapRegion?) throws -> MapRenderer {
        #if canImport(MapLibre)
        guard let region else {
            return try appleMaps("no installed region covers the trip"
                + " (set TEST_RUNNER_KAMOME_TILES_PATH to render the MapLibre souvenir map instead)")
        }
        print("KAMOME_DEMO_FILM substrate MapLibre · region bounds \(region.bounds), "
            + "terrain: \(region.terrainURL != nil)")
        let styleURL = try RecapMapStyle.resolvedStyleURL(
            styleResource: RecapMapTiles.styleResource, tilesURL: region.tilesURL,
            terrainURL: region.terrainURL
        )
        return MapLibreSnapshotProvider(styleURL: styleURL)
        #else
        return try appleMaps("MapLibre is not linked into this build")
        #endif
    }

    /// Apple Maps, carrying whatever the review render asked of it, and saying so.
    func appleMaps(_ reason: String) throws -> MapRenderer {
        let experiment = try Self.mapExperiment()
        print("KAMOME_DEMO_FILM substrate Apple Maps (\(experiment.appearance), "
            + "displayScale \(experiment.displayScale)) — \(reason)")
        return MapKitSnapshotProvider(
            displayScale: experiment.displayScale, appearance: experiment.appearance
        )
    }

    /// **A film renders on whichever substrate is available, and falling back is
    /// not a failure** (2026-08-08 substrate ADR, restated here 2026-08-22).
    ///
    /// The rule this replaces was an `XCTFail` on the no-region path. It could
    /// once be read as "you forgot the tiles path"; since the ADR it fires on
    /// every successful render, because Apple Maps is what ships and no region
    /// is installed. Arch.md §7.3: the case stopped being exercisable as a
    /// failure, so the assertion is restated to hold the rule instead of
    /// deleted with it.
    ///
    /// Not env-gated, unlike every render in this file — it takes no snapshot,
    /// no tiles and no network, and the regression it guards is silent.
    func testAFilmRendersOnWhicheverSubstrateIsAvailable() throws {
        // No installed region — today's normal state, and the shipping one.
        let fallback = try snapshotProvider(region: nil)
        XCTAssertTrue(
            fallback is MapKitSnapshotProvider,
            "with no MapLibre region a film must still render, on Apple Maps — the shipping substrate"
        )
        // Whatever the substrate, the camera contract it advertises is the one
        // the follow-cam resolver reads. Apple Maps cannot rotate and says so.
        XCTAssertFalse(
            fallback.capabilities.supportsBearing,
            "MapKit must keep declaring bearing unsupported rather than silently ignoring one"
        )
    }
}

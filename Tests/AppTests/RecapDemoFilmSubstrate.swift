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
    /// The same override `RecapReviewScene` carries. Repeated rather than shared
    /// because the two build their subject renderer differently — that scene also
    /// honours `KAMOME_SUBJECT_LENGTH_PX`, which a full film has no use for.
    /// Nothing touches the config file, so a choice made for one render can never
    /// be committed.
    static func subjectRenderer(
        style: RecapStyle, config: TrackingConfig.Export
    ) -> VehicleSubjectRenderer {
        let subjectId = HarnessEnv.value("KAMOME_SUBJECT")
        print("KAMOME_DEMO_FILM subject \(subjectId ?? VehicleCatalog.defaultSubjectId)")
        return VehicleSubjectRenderer.make(style: style, config: config, subjectId: subjectId)
    }

    /// The base map this render will use — **and falling back is not a failure**.
    /// The rule and the two overrides live in `ReviewSubstrate`, which is shared
    /// with `RecapReviewScene`; this only names the log prefix.
    func snapshotProvider(region: RecapMapRegion?) throws -> MapRenderer {
        try ReviewSubstrate.renderer(region: region, reporting: "KAMOME_DEMO_FILM")
    }

    /// **A film renders on whichever substrate is available, and falling back is
    /// not a failure** (2026-08-08 substrate ADR, restated 2026-08-22).
    ///
    /// The rule this replaces was an `XCTFail` on the no-region path. It could
    /// once be read as "you forgot the tiles path"; since the ADR it fires on
    /// every successful render, because Apple Maps is what ships and no region
    /// is installed. Arch.md §7.3: the case stopped being exercisable as a
    /// failure, so the assertion is restated to hold the rule instead of
    /// deleted with it.
    ///
    /// It asserts through `ReviewSubstrate` rather than through this harness's
    /// own wrapper, because since 2026-08-27 that is where the rule lives — and
    /// `RecapReviewScene`, which threw on the same path and killed the stills and
    /// length-limited film harnesses, now goes through it too. Testing the wrapper
    /// would have been the mistake that let the second copy survive the first fix.
    ///
    /// Not env-gated, unlike every render in this file — it takes no snapshot,
    /// no tiles and no network, and the regression it guards is silent.
    func testAFilmRendersOnWhicheverSubstrateIsAvailable() throws {
        // No installed region — today's normal state, and the shipping one.
        for label in ["KAMOME_DEMO_FILM", "KAMOME_REVIEW"] {
            let fallback = try ReviewSubstrate.renderer(region: nil, reporting: label)
            XCTAssertTrue(
                fallback is MapKitSnapshotProvider,
                "\(label): with no MapLibre region a render must still happen, on Apple Maps"
            )
            // Whatever the substrate, the camera contract it advertises is the one
            // the follow-cam resolver reads. Apple Maps cannot rotate and says so.
            XCTAssertFalse(
                fallback.capabilities.supportsBearing,
                "\(label): MapKit must keep declaring bearing unsupported, not silently ignore one"
            )
        }
        // And this harness's own wrapper still routes to it.
        XCTAssertTrue(try snapshotProvider(region: nil) is MapKitSnapshotProvider)
    }
}

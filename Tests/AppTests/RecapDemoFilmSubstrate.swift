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

    /// **What crosses a leg with no road, for a review film** — the seagull, the
    /// shipped answer (`VehicleCatalog.crossingSubjectId`), overridable per run
    /// by `KAMOME_CROSSING_SUBJECT`.
    ///
    /// 🔴 **This harness passed no crossing renderer at all until 2026-09-04**,
    /// and `FrameCompositor` reads nil as "draw the trip's own vehicle" — so the
    /// Auckland judgement film drove a **car** across the Pacific while the app
    /// drew a gull. Nothing was broken and nothing said so: the same shape as the
    /// substrate fallback `ReviewSubstrate` was built to make loud.
    static func crossingRenderer(
        style: RecapStyle, config: TrackingConfig.Export
    ) -> VehicleSubjectRenderer {
        let subjectId = HarnessEnv.value("KAMOME_CROSSING_SUBJECT") ?? VehicleCatalog.crossingSubjectId
        print("KAMOME_DEMO_FILM crossing subject \(subjectId)")
        return VehicleSubjectRenderer.make(style: style, config: config, subjectId: subjectId)
    }

    /// **What flies a crossing carrying a boarding pass** (ADR 2026-09-04) —
    /// `plane`, overridable by `KAMOME_FLIGHT_SUBJECT` so the two 8-direction
    /// sets can be judged against each other without a config edit.
    static func flightRenderer(
        style: RecapStyle, config: TrackingConfig.Export
    ) -> VehicleSubjectRenderer {
        let subjectId = HarnessEnv.value("KAMOME_FLIGHT_SUBJECT") ?? VehicleCatalog.planeSubjectId
        print("KAMOME_DEMO_FILM flight subject \(subjectId)")
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

    /// **A substrate that is locked to one appearance overrides the device's**
    /// (2026-08-28).
    ///
    /// The film follows the system appearance, and the palette drawn over the
    /// base map is selected by the same value — so the one case where those can
    /// disagree has to be settled by the renderer, not by hope. Apple Maps takes
    /// either. The souvenir map is a dark style sheet with no light variant, and
    /// a light-mode device with tiles installed would otherwise get an orange
    /// trail and a light-tuned grade over a near-black map: the halo defect's
    /// mechanism, running the other way.
    ///
    /// Not env-gated, for the same reason as the test above it: no snapshot, no
    /// tiles, no network, and the regression it guards is silent in a still.
    func testASubstrateLockedToOneAppearanceOverridesTheDevices() throws {
        let appleMaps = try ReviewSubstrate.renderer(region: nil, reporting: "KAMOME_DEMO_FILM").capabilities
        XCTAssertNil(
            appleMaps.fixedAppearance,
            "Apple Maps renders either appearance — it must not claim to be locked to one"
        )
        for requested in RecapAppearance.allCases {
            XCTAssertEqual(
                appleMaps.appearance(honouring: requested), requested,
                "a substrate with no fixed appearance must pass the device's choice through"
            )
        }

        #if canImport(MapLibre)
        // Any style URL: the capability is a property of the substrate, and this
        // takes no snapshot.
        let souvenir = MapLibreSnapshotProvider(
            styleURL: URL(fileURLWithPath: "/dev/null")
        ).capabilities
        XCTAssertEqual(
            souvenir.fixedAppearance, .dark,
            "the souvenir map's style sheet is dark and has no light variant — it must say so"
        )
        for requested in RecapAppearance.allCases {
            XCTAssertEqual(
                souvenir.appearance(honouring: requested), .dark,
                "a light-mode device must not get Kamome's light palette over the dark souvenir map"
            )
        }
        #endif
    }
}

@testable import Kamome
import KamomeExportEngine

/// **Which base map a review render draws on — one rule, one place.**
///
/// The rule: *a film renders on whichever substrate is available, and falling
/// back is not a failure.* Apple Maps has been the shipping substrate since the
/// 2026-08-08 ADR and MapLibre is parked, so no installed `.pmtiles` region is
/// the normal state rather than a missing setting.
///
/// **Why this type exists rather than the rule living where it is used.** It was
/// written twice and the copies drifted, in different directions, and both were
/// wrong:
///
/// - `RecapDemoFilmTests` **`XCTFail`ed** and then rendered anyway, so every
///   successful film reported a failure (restated 2026-08-22, `77b71b4`).
/// - `RecapReviewScene` **threw**, which killed `RecapPilotFilmTests` and
///   `RecapStopStillTests` outright — the length-limited film harness and the
///   only stills writer, dead since 2026-08-15 and not noticed until a session
///   had to spend three full 8-minute renders where stills would have done.
///
/// Fixing the first copy did nothing for the second, which is the argument for
/// one implementation: this is a **rule**, and a rule with two implementations
/// has already proved it will be corrected in only one of them.
enum ReviewSubstrate {
    /// The Apple Maps experiment, from `KAMOME_MAP_DISPLAY_SCALE` and
    /// `KAMOME_MAP_APPEARANCE` (2026-08-22).
    ///
    /// Review-only overrides for questions Chiu judges by looking. They are env
    /// rather than config keys precisely because the appearance is **still
    /// undecided** — scale 2 was chosen on 2026-08-27, light vs dark was not,
    /// because the three films never isolated that axis. A `TrackingConfig` key
    /// would ship an answer to a question still open, so the defaults here stay
    /// today's shipped behaviour.
    ///
    /// An unparseable value is refused rather than quietly ignored. A review
    /// render that silently used a different setting than the reviewer asked for
    /// is worse than one that did not run.
    struct Experiment {
        var displayScale = 1
        var appearance = MapKitSnapshotProvider.Appearance.light
    }

    static func experiment() throws -> Experiment {
        var experiment = Experiment()
        if let raw = HarnessEnv.value("KAMOME_MAP_DISPLAY_SCALE") {
            // Deliberately `Int`, matching `MapKitSnapshotProvider.displayScale`,
            // whose own comment gives the reason: the scale must divide the frame
            // exactly, and MapKit's own scales are whole numbers.
            //
            // The *arithmetic* would tolerate 1.5 — it divides 1080x1920 into a
            // 720x1280pt canvas, and would sit between today's label density and
            // scale 2's. But it is **not reachable**: the type forbids it, and
            // getting there means widening `Int` to `CGFloat` against a written
            // reason, not passing a different string here. Recorded so nobody
            // mistakes it for a value they can already try.
            guard let parsed = Int(raw), parsed >= 1 else {
                throw HarnessError("KAMOME_MAP_DISPLAY_SCALE=\(raw) is not a display scale (try 1, 2 or 3)")
            }
            experiment.displayScale = parsed
        }
        if let raw = HarnessEnv.value("KAMOME_MAP_APPEARANCE") {
            switch raw {
            case "light": experiment.appearance = .light
            case "dark": experiment.appearance = .dark
            default: throw HarnessError("KAMOME_MAP_APPEARANCE=\(raw) is not 'light' or 'dark'")
            }
        }
        return experiment
    }

    /// The base map for this render, reported under `label` so a review render
    /// always says on the console which substrate it drew — never judged.
    static func renderer(region: RecapMapRegion?, reporting label: String) throws -> MapRenderer {
        #if canImport(MapLibre)
        guard let region else {
            return try appleMaps(
                reporting: label,
                because: "no installed region covers the trip"
                    + " (set TEST_RUNNER_KAMOME_TILES_PATH to render the MapLibre souvenir map instead)"
            )
        }
        print("\(label) substrate MapLibre · region \(region.tilesURL.lastPathComponent) · terrain "
            + (region.terrainURL?.lastPathComponent ?? "NONE — the map will be flat"))
        return MapLibreSnapshotProvider(styleURL: try RecapMapStyle.resolvedStyleURL(
            styleResource: RecapMapTiles.styleResource, tilesURL: region.tilesURL,
            terrainURL: region.terrainURL
        ))
        #else
        return try appleMaps(reporting: label, because: "MapLibre is not linked into this build")
        #endif
    }

    /// Apple Maps, carrying whatever the review render asked of it, and saying so.
    private static func appleMaps(reporting label: String, because reason: String) throws -> MapRenderer {
        let experiment = try experiment()
        print("\(label) substrate Apple Maps (\(experiment.appearance), "
            + "displayScale \(experiment.displayScale)) — \(reason)")
        return MapKitSnapshotProvider(
            displayScale: experiment.displayScale, appearance: experiment.appearance
        )
    }
}

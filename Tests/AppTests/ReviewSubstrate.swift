import Foundation
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
    /// rather than config keys precisely because the answers are **still open** —
    /// scale 2 was chosen on 2026-08-27 and has not shipped. A `TrackingConfig`
    /// key would ship an answer to a question still being asked, so the defaults
    /// here stay today's shipped behaviour.
    ///
    /// `appearance` changed meaning on 2026-08-28. It used to set only the base
    /// map's trait, which meant a "dark" still was a dark Apple Maps under a
    /// palette tuned for a dark souvenir map by coincidence. Now it is the same
    /// `RecapAppearance` the app captures at export, and `RecapReviewScene` builds
    /// the style from it — so a review still is the film the app would render on a
    /// device in that appearance, rather than a half of it. The default below is
    /// still light, and it is a *stated* default in one place rather than an
    /// appearance inherited from whatever the simulator happens to be set to;
    /// every render prints which one it used.
    ///
    /// An unparseable value is refused rather than quietly ignored. A review
    /// render that silently used a different setting than the reviewer asked for
    /// is worse than one that did not run.
    struct Experiment {
        var displayScale = 1
        /// Today's shipped behaviour when the reviewer says nothing — the light
        /// Apple Maps base every film has rendered on since 2026-08-15.
        var appearance = RecapAppearance.light
    }

    /// **The OpenFreeMap evaluation switch** (`KAMOME_MAP_SUBSTRATE`, ADR
    /// 2026-09-09). Review harness only — nothing in the app reads it, and
    /// `RecapModel.snapshotProvider(for:)` is untouched, so no build behaves
    /// differently because this exists.
    ///
    /// **Why the switch lives here rather than in `RecapMapTiles`.** That lookup
    /// matches a trip against a `.pmtiles` region's own header bounds, and
    /// OpenFreeMap is a *planet* with no region file and no bounds to match — so
    /// every trip would fall back to Apple Maps no matter what path it was given.
    /// The evaluation therefore bypasses region resolution entirely instead of
    /// teaching the region lookup about a substrate that has no regions.
    ///
    /// The styles are OpenFreeMap's own hosted ones, loaded by URL. **No Kamome
    /// style is authored or bundled this round** (the ADR forbids it), and
    /// `RecapMapStyle`'s `pmtiles://` path is not touched — the parked souvenir
    /// style stays exactly as parked.
    enum Substrate: String, CaseIterable {
        case openFreeMapPositron = "positron"
        case openFreeMapLiberty = "liberty"
        case openFreeMapFiord = "fiord"
        /// **Kamome's own fork of Liberty** (Chiu 2026-09-10) — 減層, the souvenir
        /// palette, and doubled place names. Still evaluation-only: `LibertyFork`
        /// writes it to a temp file at render time and nothing ships it.
        case openFreeMapLibertyFork = "liberty-fork"

        /// OpenFreeMap serves the style, its glyphs and its sprite from absolute
        /// URLs inside the style document, so for a stock style this one URL is
        /// the whole wiring. The fork is built and written to a temp file, which
        /// resolves those same absolute URLs identically.
        func resolvedStyleURL() throws -> URL {
            guard self != .openFreeMapLibertyFork else { return try LibertyFork.resolvedStyleURL() }
            return URL(string: "https://tiles.openfreemap.org/styles/\(rawValue)")!
        }

        /// **Which appearance Kamome's palette must be drawn in over this base**,
        /// read off each style's own `background-color` layer (VERIFIED
        /// 2026-09-09 against the served style documents):
        /// Positron `rgb(242,243,240)` and Liberty `#f8f4f0` are light grounds;
        /// Fiord `#45516E` is a dark slate.
        ///
        /// Hard-coded rather than sniffed from the style JSON on purpose: three
        /// styles is not a population that needs an algorithm, and a luminance
        /// threshold would be an unreviewed rule for a decision (ADR 2026-08-27)
        /// that is Chiu's.
        /// The fork is dark because it wears the souvenir palette, which is a dark
        /// style sheet. ⚠️ **That is sequencing, not a decision** — Chiu is doing
        /// light and dark one at a time and ADR 2026-08-27 is untouched.
        var appearance: RecapAppearance {
            switch self {
            case .openFreeMapPositron, .openFreeMapLiberty: return .light
            case .openFreeMapFiord, .openFreeMapLibertyFork: return .dark
            }
        }

        /// The attribution OpenFreeMap's TileJSON declares and ODbL obliges.
        /// The OpenFreeMap clause is optional-but-asked; the OpenStreetMap clause
        /// is not optional.
        static let attribution = "OpenFreeMap © OpenMapTiles Data from OpenStreetMap"
    }

    /// The substrate the reviewer asked for, or nil for today's normal path.
    /// An unrecognised value is refused, never ignored — `HarnessEnv`'s reason.
    static func requestedSubstrate() throws -> Substrate? {
        guard let raw = HarnessEnv.value("KAMOME_MAP_SUBSTRATE") else { return nil }
        guard let substrate = Substrate(rawValue: raw) else {
            throw HarnessError(
                "KAMOME_MAP_SUBSTRATE=\(raw) is not one of "
                    + Substrate.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        return substrate
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
        // The evaluation switch is read before the region lookup, because the
        // substrate it selects has no regions to look up (see `Substrate`).
        if let substrate = try requestedSubstrate() {
            let styleURL = try substrate.resolvedStyleURL()
            print("\(label) substrate OpenFreeMap/MapLibre · style \(substrate.rawValue) "
                + "(\(styleURL.absoluteString)) · appearance \(substrate.appearance.rawValue) "
                + "— EVALUATION ONLY, no build renders this (ADR 2026-09-09)")
            return MapLibreSnapshotProvider(styleURL: styleURL, appearance: substrate.appearance)
        }
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

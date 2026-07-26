import Foundation

/// Where the recap's vector tiles live at render time (Replay MVP §2/§3).
///
/// **Why this is a lookup and not a constant.** The souvenir map is drawn from
/// self-hosted vector tiles (substrate ADR 2026-07-19), and a `.pmtiles` file
/// covers a bounded region — there is no planet-sized file to bundle. Serving
/// tiles for wherever a user actually travelled is a backend problem (spec P7);
/// until that exists, the app renders MapLibre where it *has* tiles and falls
/// back to Apple's map elsewhere, rather than shipping blank frames.
///
/// Search order, first hit wins:
/// 1. `KAMOME_TILES_PATH` — an explicit override, used by the demo/dogfood
///    renders to point at a corridor build that is far too large for git.
/// 2. Application Support — where a downloaded or side-loaded region would land.
/// 3. The app bundle — a region shipped with the build, if any.
enum RecapMapTiles {
    /// The theme whose map half these tiles feed (`Config/RecapThemes/`).
    static let styleResource = "modern-minimal"

    /// The tiles to render with, or nil when none are available — the caller
    /// then uses the MapKit provider.
    static func availableTilesURL(bundle: Bundle = .main) -> URL? {
        if let override = ProcessInfo.processInfo.environment["KAMOME_TILES_PATH"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) {
            let url = support.appendingPathComponent("tiles/\(regionFileName)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return bundle.url(forResource: regionFileName, withExtension: nil)
    }

    /// The single region file name the app looks for. One region for now; a real
    /// multi-region index arrives with tile provisioning (P7).
    static let regionFileName = "kamome-region.pmtiles"
}

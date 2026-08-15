import Foundation

/// The map region a trip is rendered against.
///
/// **This is the seam** (Chiu 2026-07-30). Exactly one thing in the app knows
/// that a trip maps to a single region file — this type — and everything
/// downstream takes what it produces. The camera receives an extent; it never
/// learns that regions, files or tile headers exist. `RecapModel` asks once and
/// passes the parts along.
///
/// International and multi-region trips are deferred, so today `resolve` answers
/// with one region or nothing. When that changes, the change is here: `bounds`
/// becomes the union of the spanning regions and `tilesURL` becomes a list, and
/// no camera or renderer code has to be found and edited to match.
struct RecapMapRegion {
    /// The vector tiles to draw from.
    let tilesURL: URL
    /// The DEM for hillshade, when one is installed. Additive — absent is fine.
    let terrainURL: URL?
    /// The region's own declared extent.
    ///
    /// This is what the opening establishing shot frames. It is the honest
    /// geographic unit rather than a guess: regions are built one per
    /// country/island, so the file's header bounds *are* the country/island, and
    /// framing to them can never show area we have no tiles for.
    let bounds: GeoBox
}

enum RecapMapRegionResolver {
    /// The region covering `trip`, or nil when none does — in which case the
    /// caller falls back to Apple's map and has no establishing extent to frame.
    static func resolve(covering trip: GeoBox, bundle: Bundle = .main) -> RecapMapRegion? {
        guard let tiles = RecapMapTiles.tilesURL(covering: trip, bundle: bundle),
              let bounds = PMTilesHeader.bounds(ofFileAt: tiles)
        else { return nil }
        return RecapMapRegion(
            tilesURL: tiles,
            terrainURL: RecapMapTiles.terrainURL(covering: trip, bundle: bundle),
            bounds: bounds
        )
    }
}

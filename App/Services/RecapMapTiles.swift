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
/// **Multi-region for the dogfood gate** (Fable review 2026-07-26, PD-7). The
/// §6 gate is three real trips in three different places, so one hard-coded
/// filename no longer does. Regions are dropped into the app's Documents folder
/// over Finder — no rebuild, no App Store round trip, and nothing bloating the
/// binary — and each one is matched against the trip being rendered by reading
/// its own PMTiles header. A region announces its own extent, so there is no
/// manifest to forget to update.
///
/// Search order, first hit wins:
/// 1. `KAMOME_TILES_PATH` — an explicit override used by demo/dogfood renders.
///    A file is taken at its word; a directory is scanned like the others.
/// 2. Documents — the Finder side-load target (`Docs/dogfood-infrastructure.md`).
/// 3. Application Support — where a downloaded region would land (spec P7).
/// 4. The app bundle — a region shipped with the build, if any.
enum RecapMapTiles {
    /// The theme whose map half these tiles feed (`Config/RecapThemes/`).
    static let styleResource = "modern-minimal"

    /// Sub-directory holding regions in each searched location.
    static let tilesDirectoryName = "tiles"
    static let terrainDirectoryName = "terrain"
    static let fileExtension = "pmtiles"

    /// The DEM covering `trip`, or nil — hillshade is additive, and a region
    /// without a terrain build still renders (flatter) rather than failing.
    /// Terrain files are named `<region>-terrain.pmtiles`; matching is by the
    /// same bounds-containment rule as the vector regions, since a DEM carries
    /// its own header bounds too.
    static func terrainURL(covering trip: GeoBox, bundle: Bundle = .main) -> URL? {
        if let override = ProcessInfo.processInfo.environment["KAMOME_TERRAIN_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue { return url }
                // A directory override gets the same two-place rule as the
                // installed locations, so pointing at either the data root or the
                // `terrain/` folder inside it both work — the render command is
                // typed by hand and should not have one correct spelling.
                for directory in [url.appendingPathComponent(terrainDirectoryName), url] {
                    if let match = bestRegion(in: directory, covering: trip, kind: .terrain) { return match }
                }
            }
        }
        for directory in terrainDirectories(bundle: bundle) {
            if let match = bestRegion(in: directory, covering: trip, kind: .terrain) { return match }
        }
        return nil
    }

    /// Where a DEM may live: a `terrain/` subfolder of each searched location,
    /// **and the locations themselves**.
    ///
    /// The root is searched because of how a region actually arrives (PD-7,
    /// 2026-07-31): a file dragged into Finder's Files pane lands loose at the top
    /// of Documents, and making a subfolder there first is a step nobody guesses.
    /// Terrain used to be looked for only under `terrain/`, so the normal drag
    /// produced a flat map with no error anywhere — the failure a fallback exists
    /// to prevent. Vector tiles already had this fallback; this gives the DEM the
    /// same one.
    ///
    /// Sharing a directory with the vector regions is safe because the two are
    /// told apart by name (`terrainSuffix`), not by location — see `regions(in:)`.
    private static func terrainDirectories(bundle: Bundle) -> [URL] {
        searchDirectories(bundle: bundle).flatMap {
            [$0.appendingPathComponent(terrainDirectoryName), $0]
        }
    }

    /// The tiles to render `trip` with, or nil when no region covers it — the
    /// caller then uses the MapKit provider.
    ///
    /// **Containment is required, not overlap.** A region that covers only part
    /// of a trip would render the rest as blank ocean, which looks like a broken
    /// app rather than a missing download; Apple's map is the honest fallback.
    /// Build region tiles with padding around the trip (the generator takes a
    /// bounds argument) rather than relaxing this.
    ///
    /// Ties break toward the **smallest** covering region: a dogfood build cut
    /// tightly around one trip carries more detail at recap zoom than a
    /// state-sized extract that happens to include it.
    static func tilesURL(covering trip: GeoBox, bundle: Bundle = .main) -> URL? {
        if let override = ProcessInfo.processInfo.environment["KAMOME_TILES_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                // An explicit path is an instruction, so a file is used as given
                // — that is what makes it useful for rendering a demo against a
                // deliberately cropped fixture.
                if !isDirectory.boolValue { return url }
                if let match = bestRegion(in: url, covering: trip) { return match }
            }
        }
        for directory in searchDirectories(bundle: bundle) {
            if let match = bestRegion(in: directory, covering: trip) { return match }
        }
        return nil
    }

    private static func searchDirectories(bundle: Bundle) -> [URL] {
        var directories: [URL] = []
        for domain in [FileManager.SearchPathDirectory.documentDirectory, .applicationSupportDirectory] {
            if let base = try? FileManager.default.url(
                for: domain, in: .userDomainMask, appropriateFor: nil, create: false
            ) {
                // Both the folder itself and a `tiles/` subfolder inside it: a
                // file dragged into Finder lands loose at the top level, while a
                // managed download would be filed under `tiles/`.
                directories.append(base)
                directories.append(base.appendingPathComponent(tilesDirectoryName))
            }
        }
        if let resources = bundle.resourceURL { directories.append(resources) }
        return directories
    }

    /// What a `.pmtiles` file in a searched directory is. Both kinds carry v3
    /// header bounds, so bounds alone cannot tell them apart — only the filename
    /// can, and `build-terrain.sh` writes `<region>-terrain.pmtiles`.
    ///
    /// This matters in both directions now that they can share a directory: a DEM
    /// picked as the vector source would render a map of nothing, and a vector
    /// region picked as the DEM would hillshade with road data.
    enum RegionKind {
        case vector
        case terrain

        func matches(_ url: URL) -> Bool {
            let isTerrain = url.deletingPathExtension().lastPathComponent.hasSuffix(terrainSuffix)
            return self == .terrain ? isTerrain : !isTerrain
        }
    }

    /// The filename marker `Deploy/bin/build-terrain.sh` writes.
    static let terrainSuffix = "-terrain"

    private static func bestRegion(in directory: URL, covering trip: GeoBox, kind: RegionKind = .vector) -> URL? {
        regions(in: directory, kind: kind)
            .filter { $0.bounds.contains(trip) }
            .min { $0.bounds.degreeArea < $1.bounds.degreeArea }?
            .url
    }

    private static func regions(in directory: URL, kind: RegionKind = .vector) -> [(url: URL, bounds: GeoBox)] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == fileExtension && kind.matches($0) }
            .compactMap { url in
                guard let bounds = PMTilesHeader.bounds(ofFileAt: url) else { return nil }
                return (url, bounds)
            }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}

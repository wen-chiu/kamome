import Foundation

/// Prepares a ready-to-render MapLibre style file from the bundled theme JSON
/// (Replay MVP §2 substrate). This stays **pure Foundation on purpose** — no
/// MapLibre import — so the tile-source wiring is deterministically unit-tested
/// without a Metal render (`MapLibreSnapshotProvider` is the SDK boundary; this
/// is not). The theme JSON ships with a sentinel tile URL
/// (`pmtiles://__KAMOME_TILES__`); at render time the real on-disk tiles path is
/// substituted in and the result is written to a temp file that the snapshotter
/// loads via `styleURL`.
enum RecapMapStyle {
    /// The placeholder the theme JSON carries in place of the tiles location, so
    /// the checked-in style stays valid for Maputnik editing while the app owns
    /// where the tiles actually live at runtime.
    static let tilesPlaceholder = "__KAMOME_TILES__"

    /// The same idea for the optional terrain-DEM file. The theme always declares
    /// the hillshade source and layer so the checked-in style stays complete and
    /// editable; when no DEM is installed they are **stripped** rather than left
    /// pointing at a path that does not exist, which MapLibre would report as a
    /// load failure and render as a blank map.
    static let terrainPlaceholder = "__KAMOME_TERRAIN__"

    /// The style id of the DEM source, so the strip knows what to remove.
    static let terrainSourceID = "kamome-terrain"

    enum ResolveError: Error, Equatable {
        case themeNotFound(resource: String)
        case placeholderMissing(resource: String)
    }

    /// Reads `<styleResource>.json` from `bundle`, substitutes the tiles path,
    /// and returns the resolved JSON string. Kept separate from file I/O so the
    /// substitution is trivially testable.
    static func resolvedStyleJSON(
        styleResource: String,
        tilesPath: String,
        terrainPath: String? = nil,
        in bundle: Bundle
    ) throws -> String {
        guard let url = bundle.url(forResource: styleResource, withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            throw ResolveError.themeNotFound(resource: styleResource)
        }
        guard json.contains(tilesPlaceholder) else {
            throw ResolveError.placeholderMissing(resource: styleResource)
        }
        // The sentinel sits inside `pmtiles://__KAMOME_TILES__`, so injecting the
        // absolute path yields `pmtiles:///abs/path.pmtiles`. The pmtiles://
        // scheme itself is declared in the theme JSON, not here — swapping the
        // ingestion path (native pmtiles:// vs mbtiles://; see
        // Docs/vector-tile-pipeline.md §5) is a theme-JSON edit, not a code edit.
        let withTiles = json.replacingOccurrences(of: tilesPlaceholder, with: tilesPath)
        guard let terrainPath else { return try stripTerrain(from: withTiles) }
        return withTiles.replacingOccurrences(of: terrainPlaceholder, with: terrainPath)
    }

    /// Removes the DEM source and every layer drawn from it. A region without a
    /// terrain build still renders — flatter, but complete — which is what keeps
    /// hillshade an additive enhancement rather than a new requirement.
    static func stripTerrain(from json: String) throws -> String {
        // Nothing to remove means nothing to rewrite. Re-serializing a style that
        // was already correct is a pointless transformation, and it is how the
        // slash-escaping bug below got the chance to bite in the first place.
        guard json.contains(terrainSourceID) else { return json }
        guard var style = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return json
        }
        if var sources = style["sources"] as? [String: Any] {
            sources.removeValue(forKey: terrainSourceID)
            style["sources"] = sources
        }
        if let layers = style["layers"] as? [[String: Any]] {
            style["layers"] = layers.filter { ($0["source"] as? String) != terrainSourceID }
        }
        // `.withoutEscapingSlashes` matters: without it Foundation writes
        // `pmtiles:\/\/file:\/\/\/…`, which is valid JSON and loads fine but makes
        // the resolved style unreadable to a human and unmatchable to a test.
        let data = try JSONSerialization.data(
            withJSONObject: style, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return String(data: data, encoding: .utf8) ?? json
    }

    /// Writes the resolved style to a temp file and returns its URL, ready for
    /// `MapLibreSnapshotProvider(styleURL:)`.
    static func resolvedStyleURL(
        styleResource: String,
        tilesURL: URL,
        terrainURL: URL? = nil,
        in bundle: Bundle = .main
    ) throws -> URL {
        // MapLibre's pmtiles handler wants a full URL after the scheme, not a
        // bare path: `pmtiles:///abs/path` fails with "unsupported URL", while
        // `pmtiles://file:///abs/path` loads (verified in-sim 2026-07-22,
        // MapLibre 6.27.0 — vector-tile-pipeline §5). So inject the file URL's
        // absoluteString, not `.path`.
        let json = try resolvedStyleJSON(
            styleResource: styleResource,
            tilesPath: tilesURL.absoluteString,
            terrainPath: terrainURL?.absoluteString,
            in: bundle
        )
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-style-\(styleResource).json")
        try json.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

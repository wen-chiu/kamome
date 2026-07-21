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
        return json.replacingOccurrences(of: tilesPlaceholder, with: tilesPath)
    }

    /// Writes the resolved style to a temp file and returns its URL, ready for
    /// `MapLibreSnapshotProvider(styleURL:)`.
    static func resolvedStyleURL(
        styleResource: String,
        tilesURL: URL,
        in bundle: Bundle = .main
    ) throws -> URL {
        let json = try resolvedStyleJSON(
            styleResource: styleResource,
            tilesPath: tilesURL.path,
            in: bundle
        )
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-style-\(styleResource).json")
        try json.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

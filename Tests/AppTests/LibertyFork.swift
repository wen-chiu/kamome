import Foundation

/// **Kamome's fork of OpenFreeMap's Liberty style — evaluation only** (Chiu,
/// 2026-09-10, on ADR 2026-09-09's evaluation).
///
/// Liberty rather than Positron because Positron is a CARTO-lineage *canvas*
/// style: low contrast is its design intent, so adding contrast to it fights the
/// thing rather than using it.
///
/// **This is a harness resource and never a shipping one.** The forked style is
/// written to a temp file at render time and handed to `MLNMapSnapshotOptions` as
/// a file URL — the same shape `RecapMapStyle` already uses for the parked
/// souvenir style. No shipping file gains an asset, which preserves the previous
/// round's property that no shipping file was touched at all.
///
/// **Three changes and no fourth**, in the order Chiu named them:
///
/// 1. **減層** — reference-map furniture comes out (`removedLayerIDs`).
/// 2. **色票** — the souvenir palette from `Config/RecapThemes/modern-minimal.json`
///    goes on, verbatim, mapped onto Liberty's equivalent layers.
/// 3. **大地名** — country / city / town labels double in size.
///
/// ⚠️ **Dark only is sequencing, not a decision.** Chiu: *"我還是想要做照系統做亮暗
/// 色調整,只是我們先一個一個來."* ADR 2026-08-27 — the film follows the device's
/// system appearance — is untouched, and the light path is not removed.
enum LibertyFork {
    /// The stock style this forks from.
    static let stockStyleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    /// The OpenFreeMap tile set the fork was authored and rendered against, so a
    /// later render can be compared with this one rather than guessed at. Their
    /// planet is rebuilt periodically and the style is whatever they serve that
    /// day; this is the only fixed point.
    static let forkedAgainstTileSet = "20260906_080001_pt"

    // MARK: - 1. 減層

    /// **Furniture a road-trip film does not need.** A convenience-store pin, a
    /// route shield and a street name are all *reference-map* affordances: they
    /// exist so a reader can navigate, and nobody navigates a recap.
    ///
    /// The road **geometry** stays — the trail needs a road network under it —
    /// and so do `waterway_line_label` / `water_name_*`, which name rivers and
    /// bays. At the three evaluation zooms those are below their own minzoom 10
    /// and simply will not appear; that is expected and is **not** lowered here.
    static let removedLayerIDs: Set<String> = [
        // POI icons and labels.
        "poi_r1", "poi_r7", "poi_r20", "poi_transit",
        // Route shields.
        "highway-shield-non-us", "highway-shield-us-interstate", "road_shield_us",
        // Street names.
        "highway-name-path", "highway-name-minor", "highway-name-major",
        // Buildings. `building-3d` is the same furniture as an extrusion, and
        // leaving it would have put 3-D blocks on a map whose flat twin was
        // deleted beside it.
        "building", "building-3d",
        // Runways, taxiways, aprons and the airport label.
        "aeroway_fill", "aeroway_runway", "aeroway_taxiway", "airport"
    ]

    // MARK: - 2. 色票

    /// The souvenir palette, copied from `Config/RecapThemes/modern-minimal.json`
    /// — the map Chiu is measuring this fork against. **Values are verbatim.**
    ///
    /// ⚠️ `label` is **not** from that file. The souvenir map has no labels at
    /// all, so there is nothing to copy: these two are a **first guess, not a
    /// tuned value**, and they are Chiu's to judge.
    enum Palette {
        static let land = "#1e2b33"
        static let water = "#060d15"
        static let waterEdge = "#4d7f86"
        static let waterway = "#3f6b72"
        static let wood = "#213039"
        static let scrub = "#132b32"
        static let wetland = "#12303a"
        static let sand = "#26313a"
        static let park = "#102a2a"
        static let ice = "#4e5c64"
        static let road = "#3a4a54"
        static let labelText = "#e8f1f4"
        static let labelHalo = "#0b141a"
    }

    /// The souvenir map's own zoom ramps, reproduced rather than re-invented.
    static func ramp(_ lowZoom: Double, _ low: Double, _ highZoom: Double, _ high: Double) -> [Any] {
        ["interpolate", ["linear"], ["zoom"], lowZoom, low, highZoom, high]
    }

    // MARK: - 3. 大地名

    /// **Only these.** `label_village`, `label_other`, POI and road names are
    /// deliberately excluded: several are deleted above anyway, and the point of
    /// the change is *selective* emphasis. Liberty caps city at 18 px and country
    /// at 17 px on a 1080 pt canvas, which is what Chiu is reacting to.
    static let doubledLabelIDs: Set<String> = [
        "label_country_1", "label_country_2", "label_country_3",
        "label_city", "label_city_capital", "label_town"
    ]

    // MARK: - The transform

    enum ForkError: Error, CustomStringConvertible {
        case notAStyle
        case noLayers
        /// Liberty changed under the fork. Refused rather than skipped: a transform
        /// that silently missed its target draws a plausible picture of the wrong
        /// thing (`Arch.md` §6).
        case unexpectedShape(String)

        var description: String {
            switch self {
            case .notAStyle: return "the fetched Liberty style is not a JSON object"
            case .noLayers: return "the fetched Liberty style has no layers array"
            case let .unexpectedShape(what): return "the fetched Liberty style is not the shape the fork edits: \(what)"
            }
        }
    }

    /// Applies all three changes to a parsed style document.
    ///
    /// Pure and synchronous so the transform is unit-testable without a network
    /// fetch or a Metal render — the same reason `RecapMapStyle` keeps its
    /// substitution separate from its file I/O.
    static func forked(from stock: [String: Any]) throws -> [String: Any] {
        guard let rawLayers = stock["layers"] as? [[String: Any]] else { throw ForkError.noLayers }
        var style = stock
        style["layers"] = rawLayers
            .filter { !removedLayerIDs.contains($0["id"] as? String ?? "") }
            .map(repainted)
            .map(enlarged)
        return style
    }

    /// One layer with the souvenir palette on it, or unchanged when the palette
    /// has nothing to say about it.
    ///
    /// ⚠️ **Layers the palette does not cover are left alone on purpose** —
    /// `boundary_2` / `boundary_3` keep their light-map grey, and
    /// `road_area_pattern` keeps its sprite pattern. Recolouring them would be a
    /// fourth change, and what they look like over a dark ground is exactly the
    /// kind of thing this round exists to show rather than to pre-empt.
    private static func repainted(_ layer: [String: Any]) -> [String: Any] {
        var layer = layer
        let id = layer["id"] as? String ?? ""
        let sourceLayer = layer["source-layer"] as? String ?? ""
        if let paint = paintOverride(id: id, sourceLayer: sourceLayer, type: layer["type"] as? String ?? "") {
            var merged = layer["paint"] as? [String: Any] ?? [:]
            for (key, value) in paint { merged[key] = value }
            // `fill-pattern` and `fill-outline-color` are light-map artwork that a
            // flat colour cannot sit under: wetland's sprite hatch would still
            // draw, and park's bright outline would still ring every park.
            if paint["fill-color"] != nil {
                merged.removeValue(forKey: "fill-pattern")
                merged.removeValue(forKey: "fill-outline-color")
            }
            layer["paint"] = merged
        }
        return layer
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func paintOverride(id: String, sourceLayer: String, type: String) -> [String: Any]? {
        switch id {
        case "background": return ["background-color": Palette.land]
        case "water": return ["fill-color": Palette.water]
        case "park": return ["fill-color": Palette.park, "fill-opacity": 0.35]
        case "park_outline": return ["line-color": Palette.park]
        case "landcover_wood": return ["fill-color": Palette.wood, "fill-opacity": 0.55]
        case "landcover_grass": return ["fill-color": Palette.scrub, "fill-opacity": 0.45]
        case "landcover_wetland": return ["fill-color": Palette.wetland, "fill-opacity": 0.45]
        case "landcover_sand": return ["fill-color": Palette.sand, "fill-opacity": 0.45]
        case "landcover_ice": return ["fill-color": Palette.ice, "fill-opacity": 1.0]
        default: break
        }
        // Liberty's six `landuse` fills — residential, pitch, track, cemetery,
        // hospital, school — have **no counterpart in the souvenir palette**,
        // which draws no landuse at all. Painting them the land colour is how a
        // palette with no entry for something is applied: they disappear into the
        // ground rather than staying a light-map tint on a dark map.
        if sourceLayer == "landuse", type == "fill" { return ["fill-color": Palette.land] }
        if sourceLayer == "waterway", type == "line" {
            return [
                "line-color": Palette.waterway,
                "line-opacity": ramp(6, 0.2, 12, 0.3)
            ]
        }
        if sourceLayer == "transportation", type == "line" { return roadPaint(id: id) }
        return nil
    }

    /// **The road rule, and the one place Liberty's own structure survives.**
    ///
    /// The souvenir map draws a single `road-skeleton` — motorway, trunk and
    /// primary only, one width. Liberty draws roughly forty transportation line
    /// layers in a casing/fill hierarchy. Colour and opacity come from the
    /// palette for **all** of them; the palette's width ramp is applied only to
    /// the fills, because giving a casing its own width would draw an outline the
    /// souvenir map does not have.
    ///
    /// A casing painted the same colour as its fill vanishes into it, which is
    /// what makes "delete the casings" unnecessary — and deleting them would have
    /// been a fourth change.
    private static func roadPaint(id: String) -> [String: Any] {
        var paint: [String: Any] = [
            "line-color": Palette.road,
            "line-opacity": ramp(8, 0.25, 14, 0.5)
        ]
        if !id.hasSuffix("_casing") { paint["line-width"] = ramp(8, 0.5, 14, 2.0) }
        return paint
    }

    /// Light text on the dark ground, and `doubledLabelIDs` at twice the size.
    ///
    /// Every surviving symbol layer gets the label colours — a label left at
    /// Liberty's `#000` on `#fff` halo would be unreadable on `#1e2b33` and would
    /// read as a bug rather than as an untuned value.
    private static func enlarged(_ layer: [String: Any]) -> [String: Any] {
        guard (layer["type"] as? String) == "symbol" else { return layer }
        var layer = layer
        var paint = layer["paint"] as? [String: Any] ?? [:]
        paint["text-color"] = Palette.labelText
        paint["text-halo-color"] = Palette.labelHalo
        layer["paint"] = paint

        guard doubledLabelIDs.contains(layer["id"] as? String ?? ""),
              var layout = layer["layout"] as? [String: Any],
              let size = layout["text-size"]
        else { return layer }
        layout["text-size"] = doubled(size)
        layer["layout"] = layout
        return layer
    }

    /// Doubles a `text-size`, whether it is a bare number or an `interpolate`
    /// expression.
    ///
    /// An interpolate's arguments alternate *stop, output* after the first three
    /// elements, so only the odd positions from index 4 are sizes — doubling the
    /// zoom stops as well would move the ramp instead of scaling it, and the
    /// labels would grow at the wrong zooms rather than being twice as big.
    static func doubled(_ size: Any) -> Any {
        if let number = size as? NSNumber, !(size is [Any]) { return number.doubleValue * 2 }
        guard var expression = size as? [Any], expression.count > 4 else { return size }
        for index in stride(from: 4, to: expression.count, by: 2) {
            guard let stop = expression[index] as? NSNumber else { continue }
            expression[index] = stop.doubleValue * 2
        }
        return expression
    }

    // MARK: - Delivery

    /// Fetches the stock style, forks it, writes it to a temp file and returns
    /// that URL.
    ///
    /// **Synchronous `Data(contentsOf:)` on purpose.** `ReviewSubstrate.renderer`
    /// is a synchronous rule shared with two other harnesses, and making it async
    /// to accommodate one evaluation substrate would change a seam that has
    /// nothing to do with this round. This is a desk harness that is already
    /// network-bound at every snapshot.
    ///
    /// Liberty's glyph, sprite and tile URLs are all absolute inside the style
    /// document (VERIFIED 2026-09-09), so a `file://` style URL resolves them
    /// exactly as the hosted one does.
    static func resolvedStyleURL() throws -> URL {
        try write(try forked(from: try stockStyle()), named: "kamome-liberty-fork.json")
    }

    /// The stock Liberty document, fetched fresh.
    static func stockStyle() throws -> [String: Any] {
        let data = try Data(contentsOf: stockStyleURL)
        guard let stock = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ForkError.notAStyle
        }
        return stock
    }

    /// Writes a style document to a temp file and returns its URL.
    ///
    /// **One filename per variant.** Whether MapLibre caches a style by URL within
    /// a process is UNKNOWN; three coast variants written to one path in one run
    /// would, if it does, render the first variant three times and label it three
    /// ways. Distinct names make the question moot.
    static func write(_ style: [String: Any], named name: String) throws -> URL {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try JSONSerialization
            .data(withJSONObject: style, options: [.withoutEscapingSlashes])
            .write(to: out, options: .atomic)
        return out
    }
}

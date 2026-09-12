import Foundation

/// **Round 3 of the Liberty fork: the prototype's linework** (Chiu 2026-09-11;
/// ADR 2026-09-09, addendum 2026-09-11).
///
/// Round 2 put the souvenir palette on Liberty and stopped at three changes. Chiu
/// lifted that cap and named the reference: his web prototype
/// (`Docs/prototype/recap_engine.html`). Its palette was already the fork's; what
/// the fork lacked was **linework** — a road skeleton instead of a web, peaks,
/// island names, a lake edge, opaque glaciers — and a coastline, which is the one
/// thing the tile schema does not hand over cleanly and is therefore rendered
/// three ways rather than decided.
///
/// Built **on top of** round 2 rather than by editing it, so round 2's picture
/// stays reproducible and `LibertyForkTests` keeps asserting what round 2 was.
///
/// ⚠️ Still evaluation only, still a harness resource, and dark-first is still
/// sequencing — ADR 2026-08-27 is untouched.
extension LibertyFork {
    /// The coastline experiment. **Not a decision** — all three are rendered and
    /// Chiu picks.
    enum Coast: String, CaseIterable {
        /// Contrast only — land against sea, no line. The fork as round 2 left it.
        case contrastOnly = "A"
        /// `fill-outline-color` on an ocean-only fill. Whether it seams is UNKNOWN.
        case oceanFillOutline = "B"
        /// A 1 px line on `class = ocean`. **Expected to seam** — see `coastLayers`.
        case oceanLine = "C"
    }

    /// Round-3 colours that are not in `modern-minimal.json`.
    enum Round3Palette {
        /// The prototype's glacier `rgba(214,232,238,.30)` pre-blended over the land
        /// `#1e2b33`. **Opaque on purpose**: a translucent ice fill double-blends
        /// where neighbouring tiles overlap — the pale cross over Vatnajökull
        /// recorded in `Docs/handoff-known-bugs.md`.
        static let glacier = "#55646b"
        /// The prototype's coast stroke `rgba(140,214,204,.28)` pre-blended over the
        /// land, for variants B and C.
        static let coast = "#3d5b5e"
        /// The souvenir map's peak accent.
        static let peak = "#9fd8e8"
    }

    /// A road class band that survives, and the zoom it appears from.
    struct SkeletonRoad {
        let id: String
        let classes: [String]
        let minzoom: Int
    }

    /// **Graded by `minzoom`, not by `["zoom"]` inside a filter** — the minzoom
    /// form is the one MapLibre Native certainly honours.
    ///
    /// ⚠️ **No `tertiary`**, even if an island reads roadless: that is reported, not
    /// patched. Ferry lines go with every other transportation layer — Kamome draws
    /// its own crossing.
    static let skeleton: [SkeletonRoad] = [
        SkeletonRoad(id: "road-major", classes: ["motorway", "trunk", "primary"], minzoom: 8),
        SkeletonRoad(id: "road-secondary", classes: ["secondary"], minzoom: 11)
    ]

    /// Peaks worth a name. **Both thresholds are first guesses**, Chiu's to judge.
    static let peakMinimumElevationM = 600
    static let peakMaximumRank = 2

    /// Round 2's fork plus round 3's map changes, with `coast` as the only thing
    /// allowed to vary between variants.
    static func forkedRound3(from stock: [String: Any], coast: Coast) throws -> [String: Any] {
        var style = try forked(from: stock)
        guard var layers = style["layers"] as? [[String: Any]] else { throw ForkError.noLayers }
        layers = replacingRoads(in: layers).map(opaqueGlacier)
        guard let water = position(of: "water", in: layers) else {
            throw ForkError.unexpectedShape("no `water` fill to put the lake edge and coast above")
        }
        layers.insert(contentsOf: [lakeEdge()] + coastLayers(coast), at: water + 1)
        layers = try withIslandLabels(layers)
        // Below every place label, so in MapLibre's collision a peak never outranks
        // a place.
        let firstPlace = layers.firstIndex { sourceLayer(of: $0) == "place" } ?? layers.count
        layers.insert(contentsOf: try peakLayers(namedLike: layers), at: firstPlace)
        style["layers"] = layers
        return style
    }

    /// Fetches stock Liberty, applies round 3 with `coast`, and writes it to a temp
    /// file named for the variant.
    static func resolvedRound3StyleURL(coast: Coast) throws -> URL {
        try write(
            try forkedRound3(from: try stockStyle(), coast: coast),
            named: "kamome-liberty-fork-r3-coast\(coast.rawValue).json"
        )
    }

    // MARK: - (a) Roads

    /// Every `transportation` layer out — 61 in stock Liberty: casings, bridges,
    /// tunnels, rail, transit, ferry — and the skeleton in where the first was.
    private static func replacingRoads(in layers: [[String: Any]]) -> [[String: Any]] {
        let first = layers.firstIndex { sourceLayer(of: $0) == "transportation" } ?? layers.count
        var kept = layers.filter { sourceLayer(of: $0) != "transportation" }
        // Everything before `first` was kept, so the index still points at the same
        // place in the shorter list.
        kept.insert(contentsOf: skeleton.map(skeletonLayer), at: min(first, kept.count))
        return kept
    }

    /// The souvenir map's `road-skeleton` look, verbatim: `#3a4a54`, opacity
    /// 0.25→0.5 and width 0.5→2.0 across z8→14.
    private static func skeletonLayer(_ road: SkeletonRoad) -> [String: Any] {
        let filter: [Any] = [
            "all",
            ["match", ["geometry-type"], ["LineString", "MultiLineString"], true, false],
            ["match", ["get", "class"], road.classes, true, false]
        ]
        let paint: [String: Any] = [
            "line-color": Palette.road,
            "line-opacity": ramp(8, 0.25, 14, 0.5),
            "line-width": ramp(8, 0.5, 14, 2.0)
        ]
        return [
            "id": road.id, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
            "minzoom": road.minzoom, "filter": filter,
            "layout": ["line-cap": "round", "line-join": "round"], "paint": paint
        ]
    }

    // MARK: - (d) Lakes, (e) glaciers, (f) the coast

    /// The souvenir map's `inland-water-edge`, **which is not the coastline**: its
    /// filter excludes `class = ocean` (VERIFIED in `modern-minimal.json`), so it
    /// strokes lakes and never the sea. ⚠️ Large lakes are tile-clipped too, so this
    /// can seam across a lake the way variant C can across the sea.
    private static func lakeEdge() -> [String: Any] {
        let filter: [Any] = ["all", ["!=", ["get", "class"], "ocean"], ["!=", ["get", "brunnel"], "tunnel"]]
        let paint: [String: Any] = [
            "line-color": Palette.waterEdge,
            "line-opacity": ramp(4, 0.34, 12, 0.42),
            "line-width": ramp(4, 0.6, 12, 1.1)
        ]
        return [
            "id": "inland-water-edge", "type": "line", "source": "openmaptiles", "source-layer": "water",
            "filter": filter, "paint": paint
        ]
    }

    /// The prototype's glacier, pre-blended and opaque. No glacier stroke this round.
    private static func opaqueGlacier(_ layer: [String: Any]) -> [String: Any] {
        guard (layer["id"] as? String) == "landcover_ice" else { return layer }
        var layer = layer
        var paint = layer["paint"] as? [String: Any] ?? [:]
        paint["fill-color"] = Round3Palette.glacier
        paint["fill-opacity"] = 1.0
        layer["paint"] = paint
        return layer
    }

    /// **The coastline, three ways.**
    ///
    /// OpenMapTiles has **no coastline line layer**: the sea is `water` with
    /// `class = ocean`, cut into tiles, so any stroke on it can also stroke the tile
    /// edges that cross open sea. That has happened in this pipeline before —
    /// `Docs/demos/phase3_5/modern-minimal/modern-minimal-coast-wide.png` shows
    /// straight horizontal lines across the sea in the coast colour, rendered before
    /// the souvenir style excluded ocean (that this is *why* it was excluded is
    /// INFERRED). The prototype never met the problem because it strokes one GeoJSON
    /// polygon, not tiles. Tile buffers are OpenFreeMap's and are not touched.
    static func coastLayers(_ coast: Coast) -> [[String: Any]] {
        let ocean: [Any] = ["==", ["get", "class"], "ocean"]
        let base: [String: Any] = ["source": "openmaptiles", "source-layer": "water", "filter": ocean]
        switch coast {
        case .contrastOnly:
            return []
        case .oceanFillOutline:
            let paint: [String: Any] = [
                "fill-color": Palette.water, "fill-outline-color": Round3Palette.coast, "fill-antialias": true
            ]
            return [base.merging(["id": "coast-ocean-outline", "type": "fill", "paint": paint]) { _, new in new }]
        case .oceanLine:
            let paint: [String: Any] = ["line-color": Round3Palette.coast, "line-width": 1.0]
            return [base.merging(["id": "coast-ocean-line", "type": "line", "paint": paint]) { _, new in new }]
        }
    }

    // MARK: - (c) Islands

    /// **Island names get the town treatment.**
    ///
    /// VERIFIED cause of round 2's ishigaki frame: its only label is
    /// `ISHIGAKI ISLAND ⏎ 石垣島`, class `island`, and Liberty's `label_other` takes
    /// every class that is *not* city/continent/country/state/town/village — so it
    /// stayed small, italic and uppercase. `island` leaves `label_other` and gets a
    /// layer built from `label_town` **as round 2 left it** (doubled, recoloured).
    ///
    /// Refuses a `label_other` filter that is not the shape it edits: a silent miss
    /// would draw islands twice, or not at all.
    private static func withIslandLabels(_ layers: [[String: Any]]) throws -> [[String: Any]] {
        guard let otherIndex = position(of: "label_other", in: layers),
              let townIndex = position(of: "label_town", in: layers)
        else { throw ForkError.unexpectedShape("no `label_other` / `label_town` to build island labels from") }
        var layers = layers
        var other = layers[otherIndex]
        guard var filter = other["filter"] as? [Any], filter.count == 5, (filter[0] as? String) == "match",
              var excluded = filter[2] as? [String]
        else { throw ForkError.unexpectedShape("`label_other`'s filter is not a class `match`") }
        excluded.append("island")
        filter[2] = excluded
        other["filter"] = filter
        layers[otherIndex] = other
        let island = islandLabel(from: layers[townIndex])
        layers.insert(island, at: otherIndex + 1)
        return layers
    }

    /// `label_town`'s doubled size and typography — upright, no uppercase transform
    /// — without its town dot. `minzoom` 8 is `label_other`'s, which is where
    /// islands appeared before.
    private static func islandLabel(from town: [String: Any]) -> [String: Any] {
        var island = town
        island["id"] = "label_island"
        island["minzoom"] = 8
        island["filter"] = ["==", ["get", "class"], "island"] as [Any]
        var layout = town["layout"] as? [String: Any] ?? [:]
        for key in ["icon-allow-overlap", "icon-image", "icon-optional", "icon-size", "text-transform"] {
            layout.removeValue(forKey: key)
        }
        layout["text-anchor"] = "center"
        island["layout"] = layout
        return island
    }

    // MARK: - (b) Peaks

    /// **A dot and a name** from `mountain_peak` (VERIFIED in the tiles, z7–14,
    /// with `ele` and `rank`).
    ///
    /// The name uses **the same two-line expression as the place labels** — Chiu
    /// kept two-line names — copied from `label_town` rather than retyped, so the
    /// two cannot drift. No elevation number.
    ///
    /// ⚠️ **Sizes are first guesses.** The souvenir map's dot (radius 1.1→2.4 at 0.5
    /// opacity) was drawn for a map with no labels and would be close to invisible
    /// at 1080 px; Chiu asked for peaks that read clearly, so the dot is larger and
    /// solid, and the name sits below the towns' size so a peak never outshouts a
    /// place. A feature with no `rank` compares against null, which MapLibre treats
    /// as not matching — such a peak is not drawn.
    private static func peakLayers(namedLike layers: [[String: Any]]) throws -> [[String: Any]] {
        guard let townIndex = position(of: "label_town", in: layers),
              let townLayout = layers[townIndex]["layout"] as? [String: Any],
              let name = townLayout["text-field"]
        else { throw ForkError.unexpectedShape("no `label_town` text-field to name peaks with") }
        let filter: [Any] = [
            "all", [">=", ["get", "ele"], peakMinimumElevationM], ["<=", ["get", "rank"], peakMaximumRank]
        ]
        let base: [String: Any] = [
            "source": "openmaptiles", "source-layer": "mountain_peak", "minzoom": 7, "filter": filter
        ]
        let dotPaint: [String: Any] = [
            "circle-color": Round3Palette.peak, "circle-radius": ramp(7, 2.5, 12, 4.0), "circle-opacity": 0.9
        ]
        let nameLayout: [String: Any] = [
            "text-field": name, "text-font": ["Noto Sans Regular"], "text-size": ramp(7, 16, 12, 20),
            "text-anchor": "top", "text-offset": [0, 0.6], "text-max-width": 8
        ]
        let namePaint: [String: Any] = [
            "text-color": Palette.labelText, "text-halo-color": Palette.labelHalo,
            "text-halo-width": 1, "text-halo-blur": 1
        ]
        let dot: [String: Any] = ["id": "mountain-peak-dot", "type": "circle", "paint": dotPaint]
        let label: [String: Any] = ["id": "mountain-peak-name", "type": "symbol", "layout": nameLayout, "paint": namePaint]
        return [dot, label].map { base.merging($0) { _, new in new } }
    }

    // MARK: - Lookup

    private static func sourceLayer(of layer: [String: Any]) -> String {
        layer["source-layer"] as? String ?? ""
    }

    private static func position(of id: String, in layers: [[String: Any]]) -> Int? {
        layers.firstIndex { ($0["id"] as? String) == id }
    }
}

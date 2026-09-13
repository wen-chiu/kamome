import Foundation

/// **Round 4 of the Liberty fork: zero seams, and terrain** (Chiu 2026-09-12;
/// ADR 2026-09-09, addendum 2026-09-12).
///
/// Round 3 rendered the coastline three ways and measured a seam in all of them.
/// Chiu chose **A — contrast only** and closed B and C: the lines are the
/// tile-clipped edges of the ocean polygon and no style setting removes them. This
/// round takes that to its conclusion — **every tile-clipped stroke goes**,
/// including the souvenir map's own lake edge — and buys the terrain Chiu asked
/// for with a hillshade instead.
///
/// Built **on top of** round 3 (coast A), which is built on round 2, so each
/// round's picture stays reproducible and each round's tests keep asserting what
/// that round was.
///
/// ⚠️ Still evaluation only, still a harness resource, still dark-first as
/// sequencing — ADR 2026-08-27 is untouched and no shipping value changes.
extension LibertyFork {
    /// Round 4's two value changes. **First guesses**, pushing the land/sea gap
    /// toward the prototype now that contrast is the only thing separating them.
    /// `sea` is the prototype's own `--ground`.
    enum Round4Palette {
        static let land = "#243440"
        static let sea = "#080b10"
    }

    /// Which peaks get drawn. Round 3's `rank <= 2` was too tight; Chiu asked for
    /// both relaxations to be tried and one shown.
    enum PeakRule: String, CaseIterable {
        /// One step looser than round 3.
        case rankAtMost3
        /// No rank at all — elevation is the whole rule.
        case elevationOnly
    }

    static let peakRelaxedMaximumRank = 3

    /// **Islands are filtered by the `place` layer's own `rank`.**
    ///
    /// ⚠️ **Measured, and it does not mean what round 4's brief assumed.** Decoding
    /// the tiles gives 石垣島 `rank=2`, 宮古島 `rank=2`, Árnes (Iceland's river
    /// islet) `rank=3`, 伊良部島 `rank=4`, 竹富島 `rank=5`. So `rank` does **not**
    /// separate an islet from an island — the islet outranks two real islands. `2`
    /// is the only threshold that drops Árnes, and the price is that neighbouring
    /// islands lose their names too. A first guess in the sense that Chiu may want
    /// the price to be different; **not** a guess about the data.
    static let islandMaximumRank = 2

    /// The DEM behind the hillshade. Mapzen terrain tiles on AWS Open Data —
    /// terrarium encoding, no key (VERIFIED 2026-09-12: `200`, a 256×256 RGB PNG).
    ///
    /// ⚠️ `maxzoom` is **13, not the souvenir map's 10**. That 10 was a property of
    /// its local pmtiles build; the island frames are z12.3–12.5, where a z10 DEM
    /// overzooms into mush.
    ///
    /// ⚠️ **§0:** this is a **third** network recipient for a render's coordinates,
    /// beside OpenFreeMap and Geoapify. Fine for a desk evaluation; it is one more
    /// line in the shipping question, which stays deferred (ADR 2026-09-09).
    static let terrainSourceID = "kamome-terrain"

    static func terrainSource() -> [String: Any] {
        [
            "type": "raster-dem",
            "tiles": ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
            "encoding": "terrarium",
            "tileSize": 256,
            "maxzoom": 13,
            "attribution": "Elevation data: Mapzen Terrain Tiles / AWS Open Data"
        ]
    }

    /// Round 3 (coast A) plus round 4's four changes.
    static func forkedRound4(
        from stock: [String: Any], hillshade: Bool, peaks: PeakRule
    ) throws -> [String: Any] {
        var style = try forkedRound3(from: stock, coast: .contrastOnly)
        guard var layers = style["layers"] as? [[String: Any]] else { throw ForkError.noLayers }

        // (a) Every tile-clipped stroke goes. Coast A already draws none; this is
        // the lake edge, which round 3 measured as a grid across Þingvallavatn.
        layers.removeAll { ($0["id"] as? String) == "inland-water-edge" }
        layers = layers.map(round4Values)

        if hillshade {
            style["sources"] = try withTerrain(style["sources"])
            guard (layers.first?["type"] as? String) == "background" else {
                throw ForkError.unexpectedShape("the first layer is not the land background")
            }
            // Directly above the land, exactly where the souvenir map puts it.
            layers.insert(hillshadeLayer(), at: 1)
        }

        layers = layers.map { relaxedPeak($0, rule: peaks) }
        layers = try islandsAboveTheCity(layers)
        style["layers"] = layers
        return style
    }

    /// Fetches stock Liberty, applies round 4, and writes it to a temp file named
    /// for the variant — one name per variant, as `write(_:named:)` explains.
    static func resolvedRound4StyleURL(hillshade: Bool, peaks: PeakRule) throws -> URL {
        try write(
            try forkedRound4(from: try stockStyle(), hillshade: hillshade, peaks: peaks),
            named: "kamome-liberty-fork-r4-\(hillshade ? "hs" : "flat")-\(peaks.rawValue).json"
        )
    }

    // MARK: - (a) The two values

    /// Repaints **by value, not by layer id**: round 2 painted Liberty's six
    /// `landuse` fills the land colour so they would disappear into the ground, and
    /// a land colour changed only on `background` would have left them showing as
    /// patches of the old one.
    private static func round4Values(_ layer: [String: Any]) -> [String: Any] {
        var layer = layer
        guard var paint = layer["paint"] as? [String: Any] else { return layer }
        for key in ["background-color", "fill-color", "line-color"] {
            switch paint[key] as? String {
            case Palette.land: paint[key] = Round4Palette.land
            case Palette.water: paint[key] = Round4Palette.sea
            default: continue
            }
        }
        layer["paint"] = paint
        return layer
    }

    // MARK: - (b) Hillshade

    private static func withTerrain(_ sources: Any?) throws -> [String: Any] {
        guard var sources = sources as? [String: Any] else {
            throw ForkError.unexpectedShape("the style has no `sources` to add the DEM to")
        }
        sources[terrainSourceID] = terrainSource()
        return sources
    }

    /// **Verbatim from `Config/RecapThemes/modern-minimal.json`** — Chiu's own
    /// tuning, not re-derived here.
    ///
    /// ⚠️ **The glaciers stay flat and that is expected**: `landcover_ice` is opaque
    /// and sits above this layer, which `Docs/handoff-known-bugs.md` records and
    /// Chiu accepted on 2026-08-06. Not to be "fixed".
    private static func hillshadeLayer() -> [String: Any] {
        [
            "id": "hillshade", "type": "hillshade", "source": terrainSourceID,
            "paint": [
                "hillshade-exaggeration": 0.85,
                "hillshade-shadow-color": "#03070d",
                "hillshade-highlight-color": "#4f7f95",
                "hillshade-accent-color": "#0a1420",
                "hillshade-illumination-direction": 315,
                "hillshade-illumination-anchor": "map"
            ]
        ]
    }

    // MARK: - (c) Peaks

    /// Relaxes round 3's filter and adds the elevation under the name.
    ///
    /// The height is a second line at 0.75 of the name's size, through a `format`
    /// expression — the name keeps the two-line place expression it was copied
    /// from, so a peak reads `名前 ⏎ 1,491 m` in the same voice as a town.
    private static func relaxedPeak(_ layer: [String: Any], rule: PeakRule) -> [String: Any] {
        let id = layer["id"] as? String ?? ""
        guard id == "mountain-peak-dot" || id == "mountain-peak-name" else { return layer }
        var layer = layer
        var filter: [Any] = ["all", [">=", ["get", "ele"], peakMinimumElevationM]]
        if rule == .rankAtMost3 { filter.append(["<=", ["get", "rank"], peakRelaxedMaximumRank]) }
        layer["filter"] = filter

        guard id == "mountain-peak-name", var layout = layer["layout"] as? [String: Any],
              let name = layout["text-field"] else { return layer }
        let height: [Any] = ["concat", ["to-string", ["get", "ele"]], " m"]
        layout["text-field"] = [
            "format", name, [String: Any](), "\n", [String: Any](), height, ["font-scale": 0.75]
        ] as [Any]
        layer["layout"] = layout
        return layer
    }

    // MARK: - (d) Islands over the city

    /// **The island name is bigger than the city's, and is placed first.**
    ///
    /// Two separate levers, because size does not win a collision: `text-size`
    /// scales off `label_city`'s own (already doubled) ramp, and the layer moves
    /// **after** the city and town layers, since MapLibre gives placement to the
    /// later of two colliding symbol layers (VERIFIED by render — see below).
    private static func islandsAboveTheCity(_ layers: [[String: Any]]) throws -> [[String: Any]] {
        guard let islandIndex = position(of: "label_island", in: layers),
              let cityLayout = layers.first(where: { ($0["id"] as? String) == "label_city" })?["layout"]
                  as? [String: Any],
              let citySize = cityLayout["text-size"]
        else { throw ForkError.unexpectedShape("no `label_island` / `label_city` to size islands against") }

        var layers = layers
        var island = layers.remove(at: islandIndex)
        var layout = island["layout"] as? [String: Any] ?? [:]
        layout["text-size"] = scaled(citySize, by: islandSizeOverCity)
        island["layout"] = layout
        island["filter"] = [
            "all", ["==", ["get", "class"], "island"], ["<=", ["get", "rank"], islandMaximumRank]
        ] as [Any]

        // ⚠️ **VERIFIED by rendering, 2026-09-13: a LATER layer wins placement.**
        // Placed *before* the city, the larger island label was the one dropped on
        // `miyakojima` and the city survived. So the island goes after the last
        // place label. Round 3's `mountain-peak-name` comment had this right; this
        // round's first attempt had it backwards, and the render said so.
        let placeLabels = ["label_city_capital", "label_city", "label_town"]
        let last = layers.lastIndex { placeLabels.contains($0["id"] as? String ?? "") }
        layers.insert(island, at: last.map { $0 + 1 } ?? layers.count)
        return layers
    }

    /// How much larger than the city an island reads. A first guess.
    static let islandSizeOverCity = 1.25

    /// Scales every *output* of a `text-size`, leaving its zoom stops alone — the
    /// same rule, and the same trap, as `doubled(_:)`.
    static func scaled(_ size: Any, by factor: Double) -> Any {
        if let number = size as? NSNumber, !(size is [Any]) { return number.doubleValue * factor }
        guard var expression = size as? [Any], expression.count > 4 else { return size }
        for index in stride(from: 4, to: expression.count, by: 2) {
            guard let stop = expression[index] as? NSNumber else { continue }
            expression[index] = stop.doubleValue * factor
        }
        return expression
    }
}

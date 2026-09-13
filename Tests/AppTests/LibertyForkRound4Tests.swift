import Foundation
@testable import Kamome
import XCTest

/// **Round 4's changes, asserted with no network and no render** (Chiu
/// 2026-09-12). Same reason as the earlier rounds: each of these fails as a
/// plausible picture of the wrong thing.
final class LibertyForkRound4Tests: XCTestCase {
    private let placeName: [Any] = [
        "case", ["has", "name:nonlatin"],
        ["concat", ["get", "name:latin"], "\n", ["get", "name:nonlatin"]],
        ["coalesce", ["get", "name_en"], ["get", "name"]]
    ]

    private func stubStyle(landFirst: Bool = true) -> [String: Any] {
        let otherFilter: [Any] = [
            "match", ["get", "class"], ["city", "continent", "country", "state", "town", "village"], false, true
        ]
        let townLayout: [String: Any] = [
            "icon-image": "circle_11_black", "text-anchor": "bottom", "text-field": placeName,
            "text-font": ["Noto Sans Regular"], "text-max-width": 8,
            "text-size": ["interpolate", ["exponential", 1.2], ["zoom"], 7, 12, 11, 14] as [Any]
        ]
        let cityLayout: [String: Any] = [
            "text-field": placeName, "text-font": ["Noto Sans Regular"],
            "text-size": ["interpolate", ["exponential", 1.2], ["zoom"], 4, 11, 7, 13, 11, 18] as [Any]
        ]
        var layers: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": "#f8f4f0"]],
            ["id": "water", "type": "fill", "source-layer": "water", "paint": ["fill-color": "rgb(158,189,255)"]],
            [
                "id": "landuse_residential", "type": "fill", "source-layer": "landuse",
                "paint": ["fill-color": "hsla(0,3%,85%,0.84)"]
            ],
            ["id": "landcover_ice", "type": "fill", "source-layer": "landcover", "paint": ["fill-color": "#e0ecec"]],
            ["id": "road_motorway", "type": "line", "source-layer": "transportation"],
            [
                "id": "label_other", "type": "symbol", "source-layer": "place", "minzoom": 8,
                "filter": otherFilter, "layout": ["text-field": placeName, "text-size": 9]
            ],
            [
                "id": "label_city", "type": "symbol", "source-layer": "place",
                "filter": ["==", ["get", "class"], "city"] as [Any], "layout": cityLayout
            ],
            [
                "id": "label_town", "type": "symbol", "source-layer": "place", "minzoom": 6,
                "filter": ["==", ["get", "class"], "town"] as [Any], "layout": townLayout
            ]
        ]
        if !landFirst { layers.insert(["id": "intruder", "type": "line", "source-layer": "boundary"], at: 0) }
        return ["version": 8, "sources": ["openmaptiles": ["type": "vector"]], "layers": layers]
    }

    private func forked(
        hillshade: Bool = true, peaks: LibertyFork.PeakRule = .rankAtMost3
    ) throws -> [String: Any] {
        try LibertyFork.forkedRound4(from: stubStyle(), hillshade: hillshade, peaks: peaks)
    }

    private func layers(_ style: [String: Any]) -> [[String: Any]] {
        style["layers"] as? [[String: Any]] ?? []
    }

    private func layer(_ style: [String: Any], _ id: String) throws -> [String: Any] {
        try XCTUnwrap(layers(style).first { $0["id"] as? String == id }, "\(id) is missing")
    }

    /// **The round's binary requirement, in the style rather than in the picture.**
    /// Every stroke that follows a tile-clipped polygon is gone — the coast (closed
    /// by Chiu) and now the lake edge, which round 3 measured as a grid across
    /// Þingvallavatn.
    func testNoTileClippedPolygonIsStrokedAnyMore() throws {
        let ids = layers(try forked()).compactMap { $0["id"] as? String }
        XCTAssertFalse(ids.contains("inland-water-edge"), "the lake edge seams exactly as the coast did")
        XCTAssertFalse(ids.contains { $0.hasPrefix("coast-") }, "coast B and C are closed, not optional")
    }

    /// **Both values move, and they move by value rather than by layer id** — round
    /// 2 painted Liberty's `landuse` fills the land colour so they would vanish into
    /// the ground, and changing only `background` would have left them as patches of
    /// the old one.
    func testTheLandAndSeaValuesMoveTogether() throws {
        let style = try forked()
        let background = try XCTUnwrap(try layer(style, "background")["paint"] as? [String: Any])
        XCTAssertEqual(background["background-color"] as? String, "#243440")
        let water = try XCTUnwrap(try layer(style, "water")["paint"] as? [String: Any])
        XCTAssertEqual(water["fill-color"] as? String, "#080b10")
        let landuse = try XCTUnwrap(try layer(style, "landuse_residential")["paint"] as? [String: Any])
        XCTAssertEqual(landuse["fill-color"] as? String, "#243440", "a landuse patch must not keep the old land colour")
    }

    /// **Hillshade is layer 2, over the DEM, with Chiu's own tuning** — and is
    /// absent, source and all, when it is not asked for.
    func testHillshadeSitsDirectlyAboveTheLandOrIsNotThereAtAll() throws {
        let style = try forked()
        XCTAssertEqual(layers(style).first?["id"] as? String, "background")
        XCTAssertEqual(layers(style)[1]["id"] as? String, "hillshade", "directly above the land, as the souvenir map has it")
        let paint = try XCTUnwrap(layers(style)[1]["paint"] as? [String: Any])
        XCTAssertEqual(paint["hillshade-exaggeration"] as? Double, 0.85)
        XCTAssertEqual(paint["hillshade-illumination-direction"] as? Int, 315)

        let sources = try XCTUnwrap(style["sources"] as? [String: Any])
        let dem = try XCTUnwrap(sources["kamome-terrain"] as? [String: Any])
        XCTAssertEqual(dem["encoding"] as? String, "terrarium")
        XCTAssertEqual(dem["maxzoom"] as? Int, 13, "the souvenir map's 10 belonged to its local pmtiles build")

        let flat = try forked(hillshade: false)
        XCTAssertFalse(layers(flat).contains { ($0["id"] as? String) == "hillshade" })
        XCTAssertNil((flat["sources"] as? [String: Any])?["kamome-terrain"], "no layer, no source")
    }

    /// **Both relaxations are reachable, and the height rides under the name.**
    func testPeaksRelaxAndCarryTheirHeight() throws {
        let ranked = try XCTUnwrap(try layer(forked(peaks: .rankAtMost3), "mountain-peak-name")["filter"] as? [Any])
        XCTAssertEqual((ranked.last as? [Any])?.last as? Int, 3, "one step looser than round 3's 2")
        let byElevation = try XCTUnwrap(
            try layer(forked(peaks: .elevationOnly), "mountain-peak-name")["filter"] as? [Any]
        )
        XCTAssertEqual(byElevation.count, 2, "elevation is the whole rule — no rank clause at all")
        XCTAssertEqual((byElevation[1] as? [Any])?.last as? Int, LibertyFork.peakMinimumElevationM)

        let layout = try XCTUnwrap(try layer(forked(), "mountain-peak-name")["layout"] as? [String: Any])
        let field = try XCTUnwrap(layout["text-field"] as? [Any])
        XCTAssertEqual(field.first as? String, "format")
        XCTAssertEqual((field.last as? [String: Any])?["font-scale"] as? Double, 0.75, "the height reads under the name")
        XCTAssertTrue("\(field)".contains("ele"), "the height comes from the feature, not from a literal")
    }

    /// **The island is larger than the city and is placed before it** — two levers,
    /// because size does not win a collision.
    func testIslandsOutrankTheCityInSizeAndInOrder() throws {
        let style = try forked()
        let island = try XCTUnwrap(try layer(style, "label_island")["layout"] as? [String: Any])
        let city = try XCTUnwrap(try layer(style, "label_city")["layout"] as? [String: Any])
        let islandSize = try XCTUnwrap(island["text-size"] as? [Any])
        let citySize = try XCTUnwrap(city["text-size"] as? [Any])
        XCTAssertEqual(
            islandSize[4] as? Double, (citySize[4] as? Double).map { $0 * LibertyFork.islandSizeOverCity },
            "the island scales off the city's already-doubled ramp"
        )
        XCTAssertGreaterThan(try XCTUnwrap(islandSize[4] as? Double), try XCTUnwrap(citySize[4] as? Double))

        // ⚠️ The direction of this assertion changed after the first render:
        // placed BEFORE the city, the island label was the one dropped. A later
        // layer wins placement, so the island must come after the city.
        let order = layers(style).compactMap { $0["id"] as? String }
        XCTAssertGreaterThan(
            try XCTUnwrap(order.firstIndex(of: "label_island")), try XCTUnwrap(order.firstIndex(of: "label_city")),
            "a later symbol layer wins the collision — VERIFIED by rendering 2026-09-13"
        )
        let filter = try XCTUnwrap(try layer(style, "label_island")["filter"] as? [Any])
        XCTAssertEqual((filter.last as? [Any])?.last as? Int, 2, "rank 2 is the only threshold that drops Árnes")
    }

    /// **A style whose first layer is not the land is refused**, because the
    /// hillshade's whole placement rule is "directly above it".
    func testRound4RefusesAStyleWhoseFirstLayerIsNotTheLand() {
        XCTAssertThrowsError(
            try LibertyFork.forkedRound4(from: stubStyle(landFirst: false), hillshade: true, peaks: .rankAtMost3)
        )
    }
}

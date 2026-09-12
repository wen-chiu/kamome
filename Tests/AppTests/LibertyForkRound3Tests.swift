import Foundation
@testable import Kamome
import XCTest

/// **Round 3's map changes, asserted with no network and no render** (Chiu
/// 2026-09-11). Same reason as `LibertyForkTests`: every one of these fails as a
/// plausible picture of the wrong thing, never as a crash.
///
/// Runs in CI — `LibertyFork.forkedRound3(from:coast:)` is pure Foundation.
final class LibertyForkRound3Tests: XCTestCase {
    /// Liberty's place-label `text-field`, verbatim.
    private let placeName: [Any] = [
        "case", ["has", "name:nonlatin"],
        ["concat", ["get", "name:latin"], "\n", ["get", "name:nonlatin"]],
        ["coalesce", ["get", "name_en"], ["get", "name"]]
    ]

    /// The stock shapes round 3 edits, one of each — not the real document, so CI
    /// does not depend on a third party's uptime.
    private func stubStyle(labelOtherFilter: [Any]? = nil) -> [String: Any] {
        let otherFilter: [Any] = labelOtherFilter ?? [
            "match", ["get", "class"], ["city", "continent", "country", "state", "town", "village"], false, true
        ]
        let ice: [String: Any] = ["fill-color": "rgba(224, 236, 236, 1)", "fill-opacity": 0.8]
        let otherLayout: [String: Any] = [
            "text-field": placeName, "text-font": ["Noto Sans Italic"], "text-transform": "uppercase", "text-size": 9
        ]
        let townLayout: [String: Any] = [
            "icon-image": "circle_11_black", "icon-size": 0.2, "text-anchor": "bottom",
            "text-field": placeName, "text-font": ["Noto Sans Regular"], "text-max-width": 8,
            "text-size": ["interpolate", ["exponential", 1.2], ["zoom"], 7, 12, 11, 14] as [Any]
        ]
        let layers: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": "#f8f4f0"]],
            ["id": "water", "type": "fill", "source-layer": "water", "paint": ["fill-color": "rgb(158,189,255)"]],
            ["id": "landcover_ice", "type": "fill", "source-layer": "landcover", "paint": ice],
            ["id": "tunnel_motorway", "type": "line", "source-layer": "transportation"],
            ["id": "road_motorway_casing", "type": "line", "source-layer": "transportation"],
            ["id": "road_motorway", "type": "line", "source-layer": "transportation"],
            ["id": "bridge_transit_rail", "type": "line", "source-layer": "transportation"],
            ["id": "boundary_2", "type": "line", "source-layer": "boundary"],
            [
                "id": "label_other", "type": "symbol", "source-layer": "place", "minzoom": 8,
                "filter": otherFilter, "layout": otherLayout
            ],
            [
                "id": "label_town", "type": "symbol", "source-layer": "place", "minzoom": 6,
                "filter": ["==", ["get", "class"], "town"] as [Any], "layout": townLayout
            ]
        ]
        return ["version": 8, "layers": layers]
    }

    private func forked(_ coast: LibertyFork.Coast = .contrastOnly) throws -> [[String: Any]] {
        try LibertyFork.forkedRound3(from: stubStyle(), coast: coast)["layers"] as? [[String: Any]] ?? []
    }

    private func layer(_ layers: [[String: Any]], _ id: String) throws -> [String: Any] {
        try XCTUnwrap(layers.first { $0["id"] as? String == id }, "\(id) is missing")
    }

    private func ids(_ layers: [[String: Any]]) -> [String] {
        layers.compactMap { $0["id"] as? String }
    }

    /// **(a)** Every road layer — casings, tunnels, bridges, rail — gives way to two
    /// skeleton layers graded by `minzoom`, and nothing below `secondary` comes back.
    func testEveryRoadLayerBecomesTwoSkeletonLayers() throws {
        let layers = try forked()
        let roads = layers.filter { ($0["source-layer"] as? String) == "transportation" }
        XCTAssertEqual(ids(roads), ["road-major", "road-secondary"])
        XCTAssertEqual(try layer(layers, "road-major")["minzoom"] as? Int, 8)
        XCTAssertEqual(
            try layer(layers, "road-secondary")["minzoom"] as? Int, 11,
            "graded by minzoom, not by a zoom expression inside the filter"
        )
        let major = try XCTUnwrap(try layer(layers, "road-major")["filter"] as? [Any])
        XCTAssertEqual((major[2] as? [Any])?[2] as? [String], ["motorway", "trunk", "primary"])
        let secondary = try XCTUnwrap(try layer(layers, "road-secondary")["filter"] as? [Any])
        XCTAssertEqual((secondary[2] as? [Any])?[2] as? [String], ["secondary"])
        XCTAssertFalse(
            "\(roads)".contains("tertiary"),
            "an island that reads roadless is reported, not patched with tertiary"
        )
        let order = ids(layers)
        XCTAssertLessThan(
            try XCTUnwrap(order.firstIndex(of: "road-major")), try XCTUnwrap(order.firstIndex(of: "boundary_2")),
            "the skeleton sits where Liberty's roads were, under the boundaries and labels"
        )
    }

    /// **(b)** Peaks carry both first-guess thresholds, are named exactly like
    /// places, show no elevation, and sit below every place label.
    func testPeaksAreFilteredNamedLikePlacesAndSitBelowThem() throws {
        let layers = try forked()
        let name = try layer(layers, "mountain-peak-name")
        let filter = try XCTUnwrap(name["filter"] as? [Any])
        XCTAssertEqual((filter[1] as? [Any])?.last as? Int, LibertyFork.peakMinimumElevationM)
        XCTAssertEqual((filter[2] as? [Any])?.last as? Int, LibertyFork.peakMaximumRank)
        XCTAssertEqual(try layer(layers, "mountain-peak-dot")["filter"] as? NSArray, filter as NSArray)

        let layout = try XCTUnwrap(name["layout"] as? [String: Any])
        XCTAssertEqual(
            layout["text-field"] as? NSArray, placeName as NSArray,
            "two-line names, the same expression the places use — and so no elevation number"
        )
        let order = ids(layers)
        XCTAssertLessThan(
            try XCTUnwrap(order.firstIndex(of: "mountain-peak-name")), try XCTUnwrap(order.firstIndex(of: "label_other")),
            "in MapLibre's collision a later layer wins; a peak must never outrank a place"
        )
    }

    /// **(c)** `island` leaves `label_other` and gets `label_town`'s *doubled*
    /// size and upright typography, without the town dot.
    func testIslandsLeaveLabelOtherForATownSizedLayerOfTheirOwn() throws {
        let layers = try forked()
        let otherFilter = try XCTUnwrap(try layer(layers, "label_other")["filter"] as? [Any])
        XCTAssertTrue((otherFilter[2] as? [String] ?? []).contains("island"))

        let island = try XCTUnwrap(try layer(layers, "label_island")["layout"] as? [String: Any])
        let town = try XCTUnwrap(try layer(layers, "label_town")["layout"] as? [String: Any])
        XCTAssertEqual(island["text-size"] as? NSArray, town["text-size"] as? NSArray)
        XCTAssertEqual(
            (island["text-size"] as? [Any])?[4] as? Double, 24,
            "12 px doubled — the island inherits round 2's doubling, not Liberty's stock size"
        )
        XCTAssertEqual(island["text-font"] as? [String], ["Noto Sans Regular"], "upright, not italic")
        XCTAssertNil(island["text-transform"], "no uppercase transform")
        XCTAssertNil(island["icon-image"], "an island is not a town dot")
    }

    /// **(d)** The lake edge is the souvenir map's, and that one never strokes the
    /// sea — it is not the coastline.
    func testTheLakeEdgeNeverStrokesTheOcean() throws {
        let filter = try XCTUnwrap(try layer(forked(), "inland-water-edge")["filter"] as? [Any])
        let notOcean: NSArray = ["!=", ["get", "class"], "ocean"]
        XCTAssertTrue(filter.contains { ($0 as? NSArray)?.isEqual(notOcean) ?? false })
    }

    /// **(e)** Glaciers are the prototype's value pre-blended, and opaque — a
    /// translucent ice fill is what drew the pale cross over Vatnajökull.
    func testGlaciersAreOpaque() throws {
        let paint = try XCTUnwrap(try layer(forked(), "landcover_ice")["paint"] as? [String: Any])
        XCTAssertEqual(paint["fill-color"] as? String, "#55646b")
        XCTAssertEqual(paint["fill-opacity"] as? Double, 1.0, "never alpha — it double-blends at tile overlaps")
    }

    /// **(f)** The three coast variants differ in their coast layer and in nothing
    /// else, and both strokes are ocean-only.
    func testTheCoastVariantsDifferOnlyInTheirCoastLayer() throws {
        let variants = try LibertyFork.Coast.allCases.map { ids(try forked($0)) }
        XCTAssertFalse(variants[0].contains { $0.hasPrefix("coast-") }, "A is contrast only")
        XCTAssertEqual(variants[1].filter { $0.hasPrefix("coast-") }, ["coast-ocean-outline"])
        XCTAssertEqual(variants[2].filter { $0.hasPrefix("coast-") }, ["coast-ocean-line"])
        for variant in variants.dropFirst() {
            XCTAssertEqual(
                variant.filter { !$0.hasPrefix("coast-") }, variants[0],
                "nothing but the coastline may vary between A, B and C, or the comparison is not one"
            )
        }
        let ocean: NSArray = ["==", ["get", "class"], "ocean"]
        for coast in [LibertyFork.Coast.oceanFillOutline, .oceanLine] {
            let stroke = try XCTUnwrap(LibertyFork.coastLayers(coast).first)
            XCTAssertEqual(stroke["filter"] as? NSArray, ocean)
        }
    }

    /// **Liberty changing under the fork is refused, not skipped.**
    func testRound3RefusesALabelOtherItDoesNotRecognise() {
        XCTAssertThrowsError(
            try LibertyFork.forkedRound3(
                from: stubStyle(labelOtherFilter: ["!=", ["get", "class"], "city"]), coast: .contrastOnly
            ),
            "a silent miss would draw islands twice, or not at all"
        )
    }
}

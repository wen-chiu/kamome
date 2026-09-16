import Foundation
@testable import Kamome
import XCTest

/// **Round 5's changes, asserted with no network and no render** (Chiu
/// 2026-09-15) — the peaks narrow to a band, or leave altogether, and **nothing
/// else about the map moves**, the island filter included.
final class LibertyForkRound5Tests: XCTestCase {
    private let placeName: [Any] = [
        "case", ["has", "name:nonlatin"],
        ["concat", ["get", "name:latin"], "\n", ["get", "name:nonlatin"]],
        ["coalesce", ["get", "name_en"], ["get", "name"]]
    ]

    private func stubStyle() -> [String: Any] {
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
        let layers: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": "#f8f4f0"]],
            ["id": "water", "type": "fill", "source-layer": "water", "paint": ["fill-color": "rgb(158,189,255)"]],
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
        return ["version": 8, "sources": ["openmaptiles": ["type": "vector"]], "layers": layers]
    }

    private func forked(_ peaks: LibertyFork.PeakBand?) throws -> [[String: Any]] {
        try LibertyFork.forkedRound5(from: stubStyle(), peaks: peaks)["layers"] as? [[String: Any]] ?? []
    }

    private func layer(_ layers: [[String: Any]], _ id: String) throws -> [String: Any] {
        try XCTUnwrap(layers.first { $0["id"] as? String == id }, "\(id) is missing")
    }

    /// **The chosen band reaches both peak layers**, dot and name alike — a dot
    /// without its name is a mark nobody can read.
    func testPeaksNarrowToTheChosenBand() throws {
        let layers = try forked(LibertyFork.Round5.chosen)
        for id in ["mountain-peak-dot", "mountain-peak-name"] {
            let filter = try XCTUnwrap(try layer(layers, id)["filter"] as? [Any])
            XCTAssertEqual(
                (filter[1] as? [Any])?.last as? Int, LibertyFork.Round5.chosen.minimumElevationM, id
            )
            XCTAssertEqual((filter.last as? [Any])?.last as? Int, LibertyFork.Round5.chosen.maximumRank, id)
        }
    }

    /// **Chiu's authorised fallback removes the layers rather than hiding them**,
    /// and disturbs nothing else.
    func testNoPeaksRemovesBothLayersAndNothingElse() throws {
        let layers = try forked(nil)
        let ids = layers.compactMap { $0["id"] as? String }
        XCTAssertFalse(ids.contains("mountain-peak-dot"))
        XCTAssertFalse(ids.contains("mountain-peak-name"))
        XCTAssertTrue(ids.contains("label_island"), "only the peaks go")
        XCTAssertEqual(layers[1]["id"] as? String, "hillshade", "round 4's terrain is untouched")
    }

    /// **Islands keep `rank <= 2`, and this round must not strip it.**
    ///
    /// Round 5 first removed the clause, reasoning that `rank` cannot tell an islet
    /// from an island — true, and **the wrong question** (Chiu, 2026-09-15). A film
    /// wants *the island it is about*, and `rank` is a prominence ordering, so
    /// 伊良部島 (`4`) and 竹富島 (`5`) dropping out is the wanted behaviour rather
    /// than a cost. The picture is the evidence: with the clause gone, `iceland`
    /// carried Árnes and Home Island as its two largest labels, and neither is a
    /// place the journey went.
    func testIslandsKeepTheirRankCeiling() throws {
        let filter = try XCTUnwrap(try layer(forked(LibertyFork.Round5.chosen), "label_island")["filter"] as? [Any])
        XCTAssertEqual(filter.first as? String, "all")
        XCTAssertEqual(
            (filter.last as? [Any])?.last as? Int, LibertyFork.islandMaximumRank,
            "round 4's ceiling survives round 5 — taking peaks away is this round's only map change"
        )
    }

    /// **Round 4's result survives round 5** — this round only takes peaks away.
    func testRoundFoursMapIsOtherwiseUnchanged() throws {
        let layers = try forked(LibertyFork.Round5.chosen)
        XCTAssertEqual(
            try layer(layers, "background")["paint"] as? [String: String], ["background-color": "#243440"]
        )
        let water = try XCTUnwrap(try layer(layers, "water")["paint"] as? [String: Any])
        XCTAssertEqual(water["fill-color"] as? String, "#080b10")
        XCTAssertFalse(
            layers.contains { ($0["id"] as? String) == "inland-water-edge" },
            "the seam source stays deleted"
        )
    }
}

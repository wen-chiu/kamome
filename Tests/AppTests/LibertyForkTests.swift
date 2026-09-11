import Foundation
@testable import Kamome
import XCTest

/// **The Liberty fork's three changes, asserted without a network fetch or a
/// render** (Chiu 2026-09-10).
///
/// The transform is where this round's judgement lives: a deletion that silently
/// missed, or a `text-size` ramp doubled at its *zoom stops* instead of its
/// sizes, produces a picture that looks plausible and answers the wrong
/// question. That is the failure shape `Arch.md` §6 names, and it is invisible in
/// a still — so it is asserted here rather than looked for by eye.
///
/// Runs in CI: `LibertyFork.forked(from:)` is pure Foundation over a dictionary.
final class LibertyForkTests: XCTestCase {
    /// A style with one layer of each kind the fork touches. Deliberately not the
    /// real Liberty document: fetching it would make a CI test depend on a third
    /// party's uptime, and the rules under test are about *shape*, not content.
    private func stubStyle() -> [String: Any] {
        [
            "version": 8,
            "layers": [
                ["id": "background", "type": "background", "paint": ["background-color": "#f8f4f0"]],
                ["id": "water", "type": "fill", "source-layer": "water", "paint": ["fill-color": "rgb(158,189,255)"]],
                ["id": "poi_r1", "type": "symbol", "source-layer": "poi"],
                ["id": "building", "type": "fill", "source-layer": "building"],
                ["id": "airport", "type": "symbol", "source-layer": "aerodrome_label"],
                ["id": "highway-shield-non-us", "type": "symbol", "source-layer": "transportation_name"],
                [
                    "id": "landcover_wetland", "type": "fill", "source-layer": "landcover",
                    "paint": ["fill-pattern": "wetland_bg_11", "fill-opacity": 0.8]
                ],
                [
                    "id": "landuse_residential", "type": "fill", "source-layer": "landuse",
                    "paint": ["fill-color": "hsla(0,3%,85%,0.84)"]
                ],
                [
                    "id": "road_motorway", "type": "line", "source-layer": "transportation",
                    "paint": ["line-color": "#fc8", "line-width": 3]
                ],
                [
                    "id": "road_motorway_casing", "type": "line", "source-layer": "transportation",
                    "paint": ["line-color": "#e9ac77", "line-width": 5]
                ],
                [
                    "id": "label_city", "type": "symbol", "source-layer": "place",
                    "layout": ["text-size": ["interpolate", ["exponential", 1.2], ["zoom"], 4, 11, 7, 13, 11, 18]],
                    "paint": ["text-color": "#000", "text-halo-color": "#fff"]
                ],
                [
                    "id": "label_village", "type": "symbol", "source-layer": "place",
                    "layout": ["text-size": 10],
                    "paint": ["text-color": "#000", "text-halo-color": "#fff"]
                ],
                ["id": "boundary_2", "type": "line", "source-layer": "boundary", "paint": ["line-color": "hsl(248,1%,41%)"]]
            ]
        ]
    }

    private func layers(_ style: [String: Any]) -> [[String: Any]] {
        style["layers"] as? [[String: Any]] ?? []
    }

    private func layer(_ style: [String: Any], _ id: String) throws -> [String: Any] {
        try XCTUnwrap(layers(style).first { $0["id"] as? String == id }, "\(id) is missing")
    }

    private func paint(_ style: [String: Any], _ id: String) throws -> [String: Any] {
        try XCTUnwrap(layer(style, id)["paint"] as? [String: Any], "\(id) has no paint")
    }

    /// **減層.** Every named piece of furniture is gone, and the road geometry and
    /// the water names Chiu asked to keep are still there.
    func testTheForkRemovesFurnitureAndKeepsTheRoadNetwork() throws {
        let forked = try LibertyFork.forked(from: stubStyle())
        let ids = Set(layers(forked).compactMap { $0["id"] as? String })

        for removed in ["poi_r1", "building", "airport", "highway-shield-non-us"] {
            XCTAssertFalse(ids.contains(removed), "\(removed) is reference-map furniture and must be deleted")
        }
        XCTAssertTrue(
            ids.contains("road_motorway"),
            "the road GEOMETRY stays — the trail needs a road network under it"
        )
        // The deletion list is a list, not a rule over source-layers: deleting by
        // `source-layer == "transportation_name"` would have taken the road names
        // AND the shields AND anything added there later, silently.
        XCTAssertEqual(
            LibertyFork.removedLayerIDs.count, 16,
            "the removal list is enumerated on purpose; changing its size is a decision"
        )
    }

    /// **色票.** The souvenir palette is on, verbatim, and the light-map artwork a
    /// flat colour cannot cover is gone with it.
    func testTheForkWearsTheSouvenirPalette() throws {
        let forked = try LibertyFork.forked(from: stubStyle())

        XCTAssertEqual(try paint(forked, "background")["background-color"] as? String, "#1e2b33")
        XCTAssertEqual(try paint(forked, "water")["fill-color"] as? String, "#060d15")
        XCTAssertEqual(try paint(forked, "road_motorway")["line-color"] as? String, "#3a4a54")

        // Wetland's sprite hatch would still draw over a flat fill, so applying a
        // colour has to take the pattern with it.
        let wetland = try paint(forked, "landcover_wetland")
        XCTAssertEqual(wetland["fill-color"] as? String, "#12303a")
        XCTAssertNil(wetland["fill-pattern"], "a light-map hatch cannot survive under a flat souvenir fill")

        // A landuse tint the palette has no entry for disappears into the ground
        // rather than staying a light-map colour on a dark map.
        XCTAssertEqual(try paint(forked, "landuse_residential")["fill-color"] as? String, "#1e2b33")

        // ⚠️ Boundaries are deliberately NOT repainted — see `repainted(_:)`.
        // This asserts the *restraint*, so that "we left it alone" cannot quietly
        // become "we forgot".
        XCTAssertEqual(try paint(forked, "boundary_2")["line-color"] as? String, "hsl(248,1%,41%)")
    }

    /// **A casing keeps the fill's colour and gains no width of its own**, which
    /// is what makes deleting the casing layers unnecessary.
    func testCasingsVanishIntoTheirFillsRatherThanBeingDeleted() throws {
        let forked = try LibertyFork.forked(from: stubStyle())
        let casing = try paint(forked, "road_motorway_casing")
        XCTAssertEqual(casing["line-color"] as? String, "#3a4a54")
        XCTAssertNil(
            casing["line-width"] as? [Any],
            "a casing given the palette's width ramp would draw an outline the souvenir map does not have"
        )
        XCTAssertNotNil(try paint(forked, "road_motorway")["line-width"] as? [Any])
    }

    /// **大地名, and only the named ones.**
    func testOnlyTheNamedLabelsDouble() throws {
        let forked = try LibertyFork.forked(from: stubStyle())
        let layout = try XCTUnwrap(layer(forked, "label_city")["layout"] as? [String: Any])
        let size = try XCTUnwrap(layout["text-size"] as? [Any])

        // The zoom stops must NOT move — doubling those would shift the ramp
        // rather than scale it, and the labels would grow at the wrong zooms.
        XCTAssertEqual(size[3] as? Double ?? Double(size[3] as? Int ?? 0), 4, "the zoom stop must stay 4")
        XCTAssertEqual(size[4] as? Double, 22, "11 px doubles to 22")
        XCTAssertEqual(size[6] as? Double, 26, "13 px doubles to 26")
        XCTAssertEqual(size[8] as? Double, 36, "18 px doubles to 36")

        let village = try XCTUnwrap(layer(forked, "label_village")["layout"] as? [String: Any])
        XCTAssertEqual(
            village["text-size"] as? Int, 10,
            "the emphasis is selective — a village is not a country"
        )
    }

    /// **Every surviving label is light on dark.** Left at Liberty's black-on-white
    /// a label would be unreadable on `#1e2b33` and would read as a bug rather
    /// than as the untuned first guess it is.
    func testEverySurvivingLabelIsLightOnDark() throws {
        let forked = try LibertyFork.forked(from: stubStyle())
        for symbol in layers(forked) where (symbol["type"] as? String) == "symbol" {
            let paint = symbol["paint"] as? [String: Any] ?? [:]
            XCTAssertEqual(paint["text-color"] as? String, "#e8f1f4", "\(symbol["id"] ?? "?")")
            XCTAssertEqual(paint["text-halo-color"] as? String, "#0b141a", "\(symbol["id"] ?? "?")")
        }
    }
}

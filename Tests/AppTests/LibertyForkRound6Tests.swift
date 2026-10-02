import Foundation
@testable import Kamome
import XCTest

/// Round 6 of the Liberty fork (Chiu 2026-10-02): the base map names no
/// settlement, and that is the only thing the round changes. Offline — the stock
/// style is the committed fixture.
final class LibertyForkRound6Tests: XCTestCase {
    private func stockStyle() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "stock-liberty", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private func ids(_ style: [String: Any]) -> [String] {
        (style["layers"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    /// No city, town, village, hamlet or suburb is named by the map: the film
    /// names the trip's own towns, and a town named twice is named badly.
    func testNoSettlementIsNamedByTheMap() throws {
        let round6 = ids(try LibertyFork.forkedRound6(from: try stockStyle()))
        XCTAssertTrue(LibertyFork.settlementLabelIDs.isDisjoint(with: round6), "\(round6)")
    }

    /// Removal is the round's only change: what is left is round 5, in order.
    /// Countries, islands, water and peaks keep their names.
    func testEverythingElseIsRoundFives() throws {
        let stock = try stockStyle()
        let round5 = ids(try LibertyFork.forkedRound5(from: stock, peaks: LibertyFork.Round5.chosen))
        let round6 = ids(try LibertyFork.forkedRound6(from: stock))
        XCTAssertEqual(round6, round5.filter { !LibertyFork.settlementLabelIDs.contains($0) })
        XCTAssertEqual(
            round5.count - round6.count, LibertyFork.settlementLabelIDs.count, "a settlement layer went missing upstream"
        )
        for kept in ["label_country_1", "label_state", "label_island", "mountain-peak-name", "water_name_point_label"] {
            XCTAssertTrue(round6.contains(kept), "\(kept) lost its name")
        }
    }

    /// A style with no settlement layers is refused, not passed through: a
    /// transform that silently missed its target draws the wrong map.
    func testRound6RefusesAStyleWithNoSettlementLabels() throws {
        var stock = try stockStyle()
        stock["layers"] = (stock["layers"] as? [[String: Any]] ?? []).filter {
            !LibertyFork.settlementLabelIDs.contains($0["id"] as? String ?? "")
        }
        XCTAssertThrowsError(try LibertyFork.forkedRound6(from: stock))
    }
}

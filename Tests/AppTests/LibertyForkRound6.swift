import Foundation
@testable import Kamome

/// # Round 6 — the base map names no settlement (Chiu 2026-10-02)
///
/// The film names the trip's own towns over the map, in Kamome's type
/// (`OverlayContent.placeNames`, ADR file 2026-10-02). With the base map's names
/// still on, a town the trip stopped in was named twice, one on top of the other
/// — and shown the render, Chiu: *「地圖本來的城鎮名關掉」*.
///
/// So every name of a place people live in leaves the map: cities, towns,
/// villages and `label_other`'s hamlets and suburbs. Countries, states, islands,
/// water and peaks keep theirs: none of them is a town, and rounds 3–5 chose
/// each of them.
///
/// **Removal is this round's only change**, and it is made last: the island and
/// peak layers are built from `label_town`'s typography (rounds 3 and 4), so the
/// layer has to exist until they have been.
extension LibertyFork {
    /// Every layer that names a settlement, in stock Liberty's own ids.
    static let settlementLabelIDs: Set<String> = [
        "label_other", "label_village", "label_town", "label_city", "label_city_capital"
    ]

    /// Round 5 as chosen, without the settlement names.
    static func forkedRound6(from stock: [String: Any]) throws -> [String: Any] {
        var style = try forkedRound5(from: stock, peaks: Round5.chosen)
        guard var layers = style["layers"] as? [[String: Any]] else { throw ForkError.noLayers }
        let before = layers.count
        layers.removeAll { settlementLabelIDs.contains($0["id"] as? String ?? "") }
        guard layers.count < before else {
            throw ForkError.unexpectedShape("round 5 drew no settlement labels for round 6 to remove")
        }
        style["layers"] = layers
        return style
    }

    static func resolvedRound6StyleURL() throws -> URL {
        try write(try forkedRound6(from: try stockStyle()), named: "kamome-liberty-fork-r6.json")
    }
}

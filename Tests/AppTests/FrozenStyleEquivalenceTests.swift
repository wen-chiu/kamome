import Foundation
@testable import Kamome
import XCTest

/// Holds the frozen dark style (bundled JSON) equivalent to the Swift round-5
/// transform applied to stock Liberty. The test loads both, strips the
/// hillshade layer (D1 undecided), and compares layer by layer — ids, order,
/// filters, paint, layout, sources.
///
/// Offline: the stock Liberty fixture is committed, never fetched.
final class FrozenStyleEquivalenceTests: XCTestCase {
    private func stockStyle() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "stock-liberty", withExtension: "json"),
            "stock-liberty.json must be committed under Tests/Fixtures/"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func frozenDarkStyle() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "openfreemap-liberty-dark", withExtension: "json"),
            "openfreemap-liberty-dark.json must be bundled"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func strippingHillshade(from style: [String: Any]) -> [String: Any] {
        var style = style
        if var sources = style["sources"] as? [String: Any] {
            sources.removeValue(forKey: LibertyFork.terrainSourceID)
            style["sources"] = sources
        }
        if let layers = style["layers"] as? [[String: Any]] {
            style["layers"] = layers.filter {
                ($0["source"] as? String) != LibertyFork.terrainSourceID
            }
        }
        return style
    }

    func testFrozenDarkMatchesRound5Transform() throws {
        let stock = try stockStyle()
        let round5 = try LibertyFork.forkedRound5(from: stock, peaks: LibertyFork.Round5.chosen)
        let swift = strippingHillshade(from: round5)
        let frozen = try frozenDarkStyle()

        let swiftLayers = try XCTUnwrap(swift["layers"] as? [[String: Any]])
        let frozenLayers = try XCTUnwrap(frozen["layers"] as? [[String: Any]])

        XCTAssertEqual(
            swiftLayers.count, frozenLayers.count,
            "layer count: swift \(swiftLayers.count) vs frozen \(frozenLayers.count)"
        )

        let swiftIDs = swiftLayers.compactMap { $0["id"] as? String }
        let frozenIDs = frozenLayers.compactMap { $0["id"] as? String }
        XCTAssertEqual(swiftIDs, frozenIDs, "layer IDs or order differ")

        for (index, (swiftLayer, frozenLayer)) in zip(swiftLayers, frozenLayers).enumerated() {
            let layerID = swiftLayer["id"] as? String ?? "(unnamed \(index))"
            comparePaint(swift: swiftLayer, frozen: frozenLayer, id: layerID)
            compareFilter(swift: swiftLayer, frozen: frozenLayer, id: layerID)
            compareLayout(swift: swiftLayer, frozen: frozenLayer, id: layerID)
        }
    }

    private func comparePaint(swift: [String: Any], frozen: [String: Any], id: String) {
        let sp = swift["paint"] as? [String: Any] ?? [:]
        let fp = frozen["paint"] as? [String: Any] ?? [:]
        let allKeys = Set(sp.keys).union(fp.keys)
        for key in allKeys.sorted() {
            let sv = sp[key]
            let fv = fp[key]
            XCTAssertTrue(
                jsonEqual(sv, fv),
                "\(id) paint.\(key): swift=\(String(describing: sv)) frozen=\(String(describing: fv))"
            )
        }
    }

    private func compareFilter(swift: [String: Any], frozen: [String: Any], id: String) {
        XCTAssertTrue(
            jsonEqual(swift["filter"], frozen["filter"]),
            "\(id) filter differs: swift=\(String(describing: swift["filter"])) frozen=\(String(describing: frozen["filter"]))"
        )
    }

    private func compareLayout(swift: [String: Any], frozen: [String: Any], id: String) {
        let sl = swift["layout"] as? [String: Any] ?? [:]
        let fl = frozen["layout"] as? [String: Any] ?? [:]
        let allKeys = Set(sl.keys).union(fl.keys)
        for key in allKeys.sorted() {
            let sv = sl[key]
            let fv = fl[key]
            XCTAssertTrue(
                jsonEqual(sv, fv),
                "\(id) layout.\(key): swift=\(String(describing: sv)) frozen=\(String(describing: fv))"
            )
        }
    }

    private func jsonEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (lhs as String, rhs as String): return lhs == rhs
        case let (lhs as Bool, rhs as Bool): return lhs == rhs
        case let (lhs as NSNumber, rhs as NSNumber):
            return lhs.doubleValue == rhs.doubleValue
        case let (lhs as [Any], rhs as [Any]):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { jsonEqual($0, $1) }
        case let (lhs as [String: Any], rhs as [String: Any]):
            return lhs.count == rhs.count && lhs.allSatisfy { jsonEqual($0.value, rhs[$0.key]) }
        default: return false
        }
    }
}

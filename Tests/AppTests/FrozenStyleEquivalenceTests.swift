import Foundation
@testable import Kamome
import XCTest

/// Holds the frozen styles (bundled JSON) equivalent to the Python transform
/// applied to stock Liberty. The tests compare layer by layer — ids, order,
/// filters, paint, layout — and also compare top-level `sources`, `glyphs`
/// and `sprite`.
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

    private func frozenStyle(resource: String) throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: resource, withExtension: "json"),
            "\(resource).json must be bundled"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Dark

    func testFrozenDarkMatchesRound5Transform() throws {
        let stock = try stockStyle()
        let round5 = try LibertyFork.forkedRound5(from: stock, peaks: LibertyFork.Round5.chosen)
        let frozen = try frozenStyle(resource: "openfreemap-liberty-dark")

        compareTopLevel(swift: round5, frozen: frozen, variant: "dark")
        try compareLayers(swift: round5, frozen: frozen, variant: "dark")
    }

    // MARK: - Light

    func testFrozenLightMatchesRound5Transform() throws {
        let stock = try stockStyle()
        let frozen = try frozenStyle(resource: "openfreemap-liberty-light")

        compareLightTopLevel(frozen: frozen)
        try compareLightLayers(frozen: frozen)
    }

    /// Light and dark must share layer ids, order, filters and layout —
    /// only colour values (paint) may differ.
    func testLightAndDarkShareStructure() throws {
        let dark = try frozenStyle(resource: "openfreemap-liberty-dark")
        let light = try frozenStyle(resource: "openfreemap-liberty-light")

        let darkLayers = dark["layers"] as? [[String: Any]] ?? []
        let lightLayers = light["layers"] as? [[String: Any]] ?? []

        let darkIDs = darkLayers.compactMap { $0["id"] as? String }
        let lightIDs = lightLayers.compactMap { $0["id"] as? String }
        XCTAssertEqual(darkIDs, lightIDs, "light and dark layer IDs or order differ")

        for (darkLayer, lightLayer) in zip(darkLayers, lightLayers) {
            let layerID = darkLayer["id"] as? String ?? "?"
            compareFilter(swift: darkLayer, frozen: lightLayer, id: "light≡dark \(layerID)")
            compareLayout(swift: darkLayer, frozen: lightLayer, id: "light≡dark \(layerID)")
        }
    }

    // MARK: - Top-level comparisons

    private func compareTopLevel(swift: [String: Any], frozen: [String: Any], variant: String) {
        XCTAssertTrue(
            jsonEqual(swift["sources"], frozen["sources"]),
            "[\(variant)] sources differ"
        )
        XCTAssertTrue(
            jsonEqual(swift["glyphs"], frozen["glyphs"]),
            "[\(variant)] glyphs differ"
        )
        XCTAssertTrue(
            jsonEqual(swift["sprite"], frozen["sprite"]),
            "[\(variant)] sprite differ"
        )
    }

    private func compareLightTopLevel(frozen: [String: Any]) {
        let sources = frozen["sources"] as? [String: Any] ?? [:]
        XCTAssertNotNil(sources["openmaptiles"], "light must have openmaptiles source")
        XCTAssertNotNil(sources[LibertyFork.terrainSourceID], "light must have terrain source")
        XCTAssertNotNil(frozen["glyphs"], "light must have glyphs")
        XCTAssertNotNil(frozen["sprite"], "light must have sprite")
    }

    // MARK: - Layer comparisons

    private func compareLayers(swift: [String: Any], frozen: [String: Any], variant: String) throws {
        let swiftLayers = try XCTUnwrap(swift["layers"] as? [[String: Any]])
        let frozenLayers = try XCTUnwrap(frozen["layers"] as? [[String: Any]])

        XCTAssertEqual(
            swiftLayers.count, frozenLayers.count,
            "[\(variant)] layer count: swift \(swiftLayers.count) vs frozen \(frozenLayers.count)"
        )

        let swiftIDs = swiftLayers.compactMap { $0["id"] as? String }
        let frozenIDs = frozenLayers.compactMap { $0["id"] as? String }
        XCTAssertEqual(swiftIDs, frozenIDs, "[\(variant)] layer IDs or order differ")

        for (swiftLayer, frozenLayer) in zip(swiftLayers, frozenLayers) {
            let layerID = swiftLayer["id"] as? String ?? "?"
            comparePaint(swift: swiftLayer, frozen: frozenLayer, id: "[\(variant)] \(layerID)")
            compareFilter(swift: swiftLayer, frozen: frozenLayer, id: "[\(variant)] \(layerID)")
            compareLayout(swift: swiftLayer, frozen: frozenLayer, id: "[\(variant)] \(layerID)")
        }
    }

    private func compareLightLayers(frozen: [String: Any]) throws {
        let frozenLayers = try XCTUnwrap(frozen["layers"] as? [[String: Any]])
        XCTAssertTrue(
            frozenLayers.contains { ($0["id"] as? String) == "hillshade" },
            "light must include the hillshade layer (D1)"
        )
        XCTAssertTrue(
            frozenLayers.contains { ($0["id"] as? String) == "mountain-peak-dot" },
            "light must include peak dots"
        )
        XCTAssertTrue(
            frozenLayers.contains { ($0["id"] as? String) == "label_island" },
            "light must include island labels"
        )
    }

    // MARK: - Helpers

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
            "\(id) filter differs"
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

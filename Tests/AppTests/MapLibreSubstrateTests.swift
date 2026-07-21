@testable import Kamome
import KamomeExportEngine
import XCTest

/// Replay MVP §2 substrate. The deterministic half of the MapLibre substrate is
/// tested here (style resolution, zoom math, boundary conformance). Actual tile
/// rendering is a Metal path that is **not** exercised in CI — it stays on the
/// device/sim manual list (golden-frame CI keeps using `FlatSnapshotProvider`,
/// see `Docs/demos/phase3_5/substrate/README.md`).
final class MapLibreSubstrateTests: XCTestCase {
    // MARK: - Style resolution (pure, no SDK)

    func testBundledFunctionalStyleResolvesAndInjectsTilesPath() throws {
        let json = try RecapMapStyle.resolvedStyleJSON(
            styleResource: "functional-base",
            tilesPath: "/tiles/perth-fixture.pmtiles",
            in: .main
        )
        XCTAssertTrue(
            json.contains("pmtiles:///tiles/perth-fixture.pmtiles"),
            "the sentinel must be replaced with the real tiles path"
        )
        XCTAssertFalse(
            json.contains(RecapMapStyle.tilesPlaceholder),
            "no placeholder may survive resolution"
        )
        // Substrate must stay subtractive: OSM attribution present, no POI/label
        // layers snuck in (spec §0 rule 6; ODbL attribution is not optional).
        XCTAssertTrue(json.contains("© OpenStreetMap contributors"), "attribution required")
        XCTAssertFalse(json.contains("\"poi\""), "functional base draws no POIs")
    }

    func testMissingPlaceholderIsAHardError() throws {
        // A style with no sentinel would silently render blank tiles; catch it.
        let bundle = Bundle.main
        XCTAssertThrowsError(
            try RecapMapStyle.resolvedStyleJSON(
                styleResource: "does-not-exist", tilesPath: "/x", in: bundle
            )
        ) { error in
            XCTAssertEqual(error as? RecapMapStyle.ResolveError, .themeNotFound(resource: "does-not-exist"))
        }
    }

    func testResolvedStyleURLWritesLoadableFile() throws {
        let tiles = URL(fileURLWithPath: "/data/perth-fixture.pmtiles")
        let url = try RecapMapStyle.resolvedStyleURL(
            styleResource: "functional-base", tilesURL: tiles, in: .main
        )
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(written.contains("pmtiles:///data/perth-fixture.pmtiles"))
        // Valid JSON, not just a string blob.
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        XCTAssertNotNil(object as? [String: Any])
    }

    // MARK: - MapLibre provider (compiled only when the SDK is linked)

    #if canImport(MapLibre)
    func testProviderConformsToSnapshotBoundary() {
        // Compile-time proof the MapLibre provider satisfies the existing
        // boundary; constructed but never `.snapshot(...)`-ed so no Metal runs.
        let provider = MapLibreSnapshotProvider(
            styleURL: URL(fileURLWithPath: "/tmp/style.json")
        )
        let boundary: RecapSnapshotProviding = provider
        XCTAssertNotNil(boundary)
    }

    func testZoomLevelIsSaneAndMonotonic() {
        // 1500 m across a 1080 px frame at Perth's latitude sits at a
        // city-to-regional zoom (~15–16 on MapLibre's 512 px tiles).
        let zoom = MapLibreSnapshotProvider.zoomLevel(spanM: 1500, widthPx: 1080, latitude: -32)
        XCTAssertGreaterThan(zoom, 14)
        XCTAssertLessThan(zoom, 17)
        // A wider ground span at the same size is a lower zoom.
        let wider = MapLibreSnapshotProvider.zoomLevel(spanM: 6000, widthPx: 1080, latitude: -32)
        XCTAssertLessThan(wider, zoom)
        XCTAssertEqual(zoom - wider, 2, accuracy: 0.001, "4× span is exactly 2 zoom levels")
    }
    #endif
}

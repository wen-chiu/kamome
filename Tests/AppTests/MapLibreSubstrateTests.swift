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
            tilesPath: "file:///tiles/perth-fixture.pmtiles",
            in: .main
        )
        XCTAssertTrue(
            json.contains("pmtiles://file:///tiles/perth-fixture.pmtiles"),
            "the sentinel must be replaced with the real tiles URL"
        )
        XCTAssertFalse(
            json.contains(RecapMapStyle.tilesPlaceholder),
            "no placeholder may survive resolution"
        )
        // Substrate must stay subtractive: OSM attribution present, no POI/label
        // layers snuck in (spec §0 rule 6; ODbL attribution is not optional).
        // Asserted against the constant the *film* now draws (ADR 2026-09-12),
        // not against a literal: the style sheet and the exported frame must
        // credit the same source in the same words, and two literals is how
        // they would drift apart without anything going red.
        XCTAssertTrue(
            json.contains(RecapMapAttribution.openStreetMap),
            "attribution required, and it must match what the film draws"
        )
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
        // MapLibre needs a full URL after the scheme: pmtiles://file:///…
        XCTAssertTrue(written.contains("pmtiles://file:///data/perth-fixture.pmtiles"))
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
            styleURL: URL(fileURLWithPath: "/tmp/style.json"),
            attribution: RecapMapAttribution.openStreetMap
        )
        let boundary: MapRenderer = provider
        XCTAssertNotNil(boundary)
    }

    /// **The substrate declares the credit it was built for, and the two hosts
    /// of OpenStreetMap's data are not interchangeable** (ADR 2026-09-12).
    ///
    /// The render loop reads `capabilities.attribution` and draws it on every
    /// frame, so this is the join between "which tiles did we fetch" and "what
    /// does the published film say about them". A provider that answered the
    /// wrong one would put a *false* credit on a film, which `CLAUDE.md` rule 5
    /// treats as worse than a missing one.
    ///
    /// ⚠️ **What this cannot reach: `options.showsAttribution = false`.** That
    /// line lives inside `snapshot(...)`, which is a Metal path CI never runs
    /// (this file's own header). It is held by the desk render in the PR and by
    /// `RecapMapCreditTests`, which is what makes turning it off safe.
    func testTheProviderDeclaresTheCreditItWasBuiltFor() {
        for attribution in [RecapMapAttribution.openStreetMap, RecapMapAttribution.openFreeMap] {
            let provider = MapLibreSnapshotProvider(
                styleURL: URL(fileURLWithPath: "/tmp/style.json"), attribution: attribution
            )
            XCTAssertEqual(
                provider.capabilities.attribution, attribution,
                "a film must credit the host whose tiles it actually drew"
            )
        }
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

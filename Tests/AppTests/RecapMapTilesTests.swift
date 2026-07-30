@testable import Kamome
import XCTest

/// Multi-region tile selection for the §6 dogfood gate (PD-7).
///
/// The gate is three real trips in three places, with regions side-loaded over
/// Finder. What has to hold is: a region announces its own extent (so nobody has
/// to maintain a manifest), a trip renders on tiles that actually cover it, and
/// anything else falls back to Apple's map rather than to blank ocean.
final class RecapMapTilesTests: XCTestCase {
    /// The committed Perth-corridor fixture — a real Planetiler artifact, so the
    /// header decoding is proven against a file we did not write by hand.
    private var fixtureTiles: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/AppTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures/tiles/perth-2026-07-19.pmtiles")
    }

    // MARK: - Header

    func testReadsBoundsFromARealPlanetilerArtifact() throws {
        let bounds = try XCTUnwrap(PMTilesHeader.bounds(ofFileAt: fixtureTiles))
        // The crop `generate_tiles.sh` asks for: 114.96,-34.00,115.16,-33.78.
        XCTAssertEqual(bounds.minLon, 114.96, accuracy: 0.01)
        XCTAssertEqual(bounds.minLat, -34.00, accuracy: 0.01)
        XCTAssertEqual(bounds.maxLon, 115.16, accuracy: 0.01)
        XCTAssertEqual(bounds.maxLat, -33.78, accuracy: 0.01)
    }

    /// An unreadable header must read as "no idea", never as a guess — a wrong
    /// guess renders a blank map, which looks like a broken app.
    func testRejectsAnythingItCannotActuallyRead() {
        var header = [UInt8](repeating: 0, count: 127)
        XCTAssertNil(PMTilesHeader.bounds(inHeader: header), "all-zero is not a real region")

        header.replaceSubrange(0..<7, with: Array("PMTiles".utf8))
        header[7] = 4  // a spec version this code has never seen
        XCTAssertNil(PMTilesHeader.bounds(inHeader: header), "an unknown version must not be decoded")

        header[7] = 3
        XCTAssertNil(PMTilesHeader.bounds(inHeader: header), "v3 with degenerate bounds is still unusable")

        XCTAssertNil(PMTilesHeader.bounds(inHeader: Array(header.prefix(64))), "a truncated header")
        XCTAssertNil(PMTilesHeader.bounds(ofFileAt: URL(fileURLWithPath: "/nope/missing.pmtiles")))
    }

    /// Round-trips a synthetic header so the byte offsets are pinned independently
    /// of whatever one fixture happens to contain.
    func testDecodesSignedE7BoundsAtTheSpecOffsets() throws {
        var header = [UInt8](repeating: 0, count: 127)
        header.replaceSubrange(0..<7, with: Array("PMTiles".utf8))
        header[7] = 3
        func write(_ degrees: Double, at offset: Int) {
            let raw = UInt32(bitPattern: Int32(degrees * 1e7))
            for byte in 0..<4 { header[offset + byte] = UInt8((raw >> (8 * UInt32(byte))) & 0xff) }
        }
        // Southern + eastern hemisphere, so both signs are exercised.
        write(120.5, at: 102)    // min lon
        write(-34.25, at: 106)   // min lat
        write(121.75, at: 110)   // max lon
        write(-33.5, at: 114)    // max lat

        let bounds = try XCTUnwrap(PMTilesHeader.bounds(inHeader: header))
        XCTAssertEqual(bounds.minLon, 120.5, accuracy: 1e-6)
        XCTAssertEqual(bounds.minLat, -34.25, accuracy: 1e-6)
        XCTAssertEqual(bounds.maxLon, 121.75, accuracy: 1e-6)
        XCTAssertEqual(bounds.maxLat, -33.5, accuracy: 1e-6)
    }

    // MARK: - Region selection

    private let margaretRiver = GeoBox(minLat: -33.98, minLon: 115.00, maxLat: -33.90, maxLon: 115.10)

    /// Writes a `.pmtiles` file that is nothing but a valid header — enough for
    /// the lookup, which never opens the tile data.
    private func writeRegion(_ name: String, _ box: GeoBox, into directory: URL) throws {
        var header = [UInt8](repeating: 0, count: 127)
        header.replaceSubrange(0..<7, with: Array("PMTiles".utf8))
        header[7] = 3
        func write(_ degrees: Double, at offset: Int) {
            let raw = UInt32(bitPattern: Int32(degrees * 1e7))
            for byte in 0..<4 { header[offset + byte] = UInt8((raw >> (8 * UInt32(byte))) & 0xff) }
        }
        write(box.minLon, at: 102)
        write(box.minLat, at: 106)
        write(box.maxLon, at: 110)
        write(box.maxLat, at: 114)
        try Data(header).write(to: directory.appendingPathComponent("\(name).pmtiles"))
    }

    private func makeTilesDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-tiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func lookup(in directory: URL, covering trip: GeoBox) -> URL? {
        setenv("KAMOME_TILES_PATH", directory.path, 1)
        defer { unsetenv("KAMOME_TILES_PATH") }
        return RecapMapTiles.tilesURL(covering: trip)
    }

    func testPicksTheRegionCoveringTheTrip() throws {
        let directory = try makeTilesDirectory()
        try writeRegion("taiwan", GeoBox(minLat: 21.7, minLon: 119.0, maxLat: 25.4, maxLon: 122.1), into: directory)
        try writeRegion("perth", GeoBox(minLat: -34.5, minLon: 114.5, maxLat: -33.0, maxLon: 116.0), into: directory)

        let chosen = try XCTUnwrap(lookup(in: directory, covering: margaretRiver))
        XCTAssertEqual(chosen.lastPathComponent, "perth.pmtiles")
    }

    /// Ties break toward the tightest covering region: a build cut around one
    /// dogfood trip carries more detail at recap zoom than a state-sized extract.
    func testPrefersTheTightestCoveringRegion() throws {
        let directory = try makeTilesDirectory()
        try writeRegion("wa-state", GeoBox(minLat: -35.5, minLon: 113.0, maxLat: -31.0, maxLon: 119.0), into: directory)
        try writeRegion("margaret-river", GeoBox(minLat: -34.0, minLon: 114.9, maxLat: -33.8, maxLon: 115.2), into: directory)

        let chosen = try XCTUnwrap(lookup(in: directory, covering: margaretRiver))
        XCTAssertEqual(chosen.lastPathComponent, "margaret-river.pmtiles")
    }

    /// Partial coverage is not coverage. Half a trip on tiles and half on blank
    /// ocean reads as a broken app; Apple's map is the honest fallback, which is
    /// what a nil here selects.
    func testAPartiallyOverlappingRegionIsNotUsed() throws {
        let directory = try makeTilesDirectory()
        // Covers the west half of the trip only.
        try writeRegion("half", GeoBox(minLat: -34.0, minLon: 114.9, maxLat: -33.8, maxLon: 115.04), into: directory)
        XCTAssertNil(lookup(in: directory, covering: margaretRiver))
    }

    func testNoRegionsAtAllFallsBack() throws {
        XCTAssertNil(lookup(in: try makeTilesDirectory(), covering: margaretRiver))
    }

    /// A corrupt or half-copied file must not take the whole lookup down with it
    /// — a side-load is a drag-and-drop, and interrupted copies happen.
    func testAnUnreadableRegionIsSkippedRatherThanFatal() throws {
        let directory = try makeTilesDirectory()
        try Data("not pmtiles".utf8).write(to: directory.appendingPathComponent("truncated.pmtiles"))
        try writeRegion("perth", GeoBox(minLat: -34.5, minLon: 114.5, maxLat: -33.0, maxLon: 116.0), into: directory)

        let chosen = try XCTUnwrap(lookup(in: directory, covering: margaretRiver))
        XCTAssertEqual(chosen.lastPathComponent, "perth.pmtiles")
    }

    /// An explicit `KAMOME_TILES_PATH` file is an instruction, not a candidate —
    /// that is what lets a demo render against a deliberately cropped fixture.
    func testAnExplicitFilePathIsTakenAtItsWord() {
        setenv("KAMOME_TILES_PATH", fixtureTiles.path, 1)
        defer { unsetenv("KAMOME_TILES_PATH") }
        // A trip far outside the fixture's crop still gets the named file.
        let taipei = GeoBox(minLat: 25.0, minLon: 121.5, maxLat: 25.1, maxLon: 121.6)
        XCTAssertEqual(RecapMapTiles.tilesURL(covering: taipei), fixtureTiles)
    }

    // MARK: - Trip bounds

    func testTripBoundsEncloseEveryRoutePoint() throws {
        let box = try XCTUnwrap(GeoBox.enclosing([
            (lat: -33.95, lon: 115.07), (lat: -33.86, lon: 115.10), (lat: -33.98, lon: 114.99)
        ]))
        XCTAssertEqual(box.minLat, -33.98, accuracy: 1e-9)
        XCTAssertEqual(box.maxLat, -33.86, accuracy: 1e-9)
        XCTAssertEqual(box.minLon, 114.99, accuracy: 1e-9)
        XCTAssertEqual(box.maxLon, 115.10, accuracy: 1e-9)
        XCTAssertNil(GeoBox.enclosing([]))
    }

    /// The end-to-end shape the dogfood gate relies on: a real trip's bounds
    /// against the real fixture region.
    func testTheCommittedFixtureCoversTheCorridorDemoTrip() throws {
        let bounds = try XCTUnwrap(PMTilesHeader.bounds(ofFileAt: fixtureTiles))
        XCTAssertTrue(bounds.contains(margaretRiver), "the demo corridor must sit inside the fixture crop")
    }

    // MARK: - Terrain (hillshade is additive, never required)

    /// A region with no DEM must still render. The theme always declares the
    /// hillshade source so the checked-in style stays editable, so resolution
    /// has to remove it — leaving a `pmtiles://` path that does not resolve is
    /// reported by MapLibre as a load failure and renders as a blank map.
    func testStyleStripsHillshadeWhenNoTerrainIsInstalled() throws {
        let json = try RecapMapStyle.resolvedStyleJSON(
            styleResource: RecapMapTiles.styleResource,
            tilesPath: "file:///tiles/nz.pmtiles",
            terrainPath: nil,
            in: .main
        )
        XCTAssertFalse(json.contains(RecapMapStyle.terrainSourceID), "the DEM source must be gone")
        XCTAssertFalse(json.contains(RecapMapStyle.terrainPlaceholder), "no placeholder may survive")
        XCTAssertFalse(json.contains("\"hillshade\""), "and no layer may be left drawing from it")
        // The rest of the style is untouched and still loadable.
        XCTAssertTrue(json.contains("pmtiles://file:///tiles/nz.pmtiles"))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testStyleKeepsHillshadeAndInjectsTheDEMPathWhenTerrainExists() throws {
        let json = try RecapMapStyle.resolvedStyleJSON(
            styleResource: RecapMapTiles.styleResource,
            tilesPath: "file:///tiles/nz.pmtiles",
            terrainPath: "file:///terrain/nz-terrain.pmtiles",
            in: .main
        )
        XCTAssertTrue(json.contains("pmtiles://file:///terrain/nz-terrain.pmtiles"))
        XCTAssertTrue(json.contains("terrarium"), "the DEM encoding must reach MapLibre")
        XCTAssertFalse(json.contains(RecapMapStyle.terrainPlaceholder))
    }

    /// Foundation escapes `/` as `\/` by default, which is valid JSON but makes
    /// every tile URL in the resolved style unreadable — and it only bit because
    /// stripping terrain re-serializes. Both halves are guarded here.
    func testResolutionNeverEscapesSlashesInTileURLs() throws {
        let json = try RecapMapStyle.resolvedStyleJSON(
            styleResource: RecapMapTiles.styleResource,
            tilesPath: "file:///tiles/nz.pmtiles",
            terrainPath: nil,
            in: .main
        )
        XCTAssertFalse(json.contains("\\/"), "escaped slashes in: \(json.prefix(200))")
    }

    /// The seam (Chiu 2026-07-30): one place knows a trip maps to one region.
    /// It answers with the tiles, the optional DEM, and the extent the opening
    /// establishing shot frames — the camera never learns files exist.
    func testRegionResolverAnswersWithTilesAndTheEstablishingExtent() throws {
        setenv("KAMOME_TILES_PATH", fixtureTiles.path, 1)
        defer { unsetenv("KAMOME_TILES_PATH") }

        let region = try XCTUnwrap(RecapMapRegionResolver.resolve(covering: margaretRiver))
        XCTAssertEqual(region.tilesURL, fixtureTiles)
        // The extent is the region's own declared bounds, which must contain the
        // trip — that is what makes it safe to frame the opening to.
        XCTAssertTrue(region.bounds.contains(margaretRiver))
        XCTAssertNil(region.terrainURL, "no DEM installed for the fixture corridor")
    }

    func testRegionResolverAnswersNilWhenNothingCoversTheTrip() throws {
        let directory = try makeTilesDirectory()
        setenv("KAMOME_TILES_PATH", directory.path, 1)
        defer { unsetenv("KAMOME_TILES_PATH") }
        XCTAssertNil(RecapMapRegionResolver.resolve(covering: margaretRiver))
    }
}

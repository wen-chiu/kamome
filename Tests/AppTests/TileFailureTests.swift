#if canImport(MapLibre)
@testable import Kamome
import KamomeExportEngine
import MapLibre
import XCTest

/// **Part D — measure, not assume.** The doc comment on
/// `RecapExportJob+Render.snapshotProvider` states five failure paths. Paths 3
/// and 4 (unreachable host, HTTP error) claim MLNMapSnapshotter fires its
/// completion with an NSError. Path 5 claims partial failure yields a
/// successful-but-blank image. None was measured until this test.
///
/// A frozen style whose tile host is replaced with `tiles.unresolvable.invalid`
/// (an IANA reserved name that cannot resolve) drives the snapshotter and
/// records what comes back.
final class TileFailureTests: XCTestCase {
    /// DNS failure (all hosts unreachable) must surface as an error, not a
    /// blank image.
    func testUnreachableTileHostReturnsAnError() async throws {
        let styleURL = try styleWithUnresolvableHost(replacingAll: true)
        let error = try await snapshotError(styleURL: styleURL)
        let ns = error as NSError
        print("all-unreachable: domain=\(ns.domain) code=\(ns.code)")
    }

    /// Tiles-only failure (sprite and glyphs reachable, vector tiles not).
    /// VERIFIED 2026-09-17: `MLNErrorDomain` code 6.
    func testUnreachableTilesOnlyReturnsAnError() async throws {
        let styleURL = try styleWithUnresolvableHost(replacingAll: false)
        let error = try await snapshotError(styleURL: styleURL)
        let ns = error as NSError
        print("tiles-only: domain=\(ns.domain) code=\(ns.code)")
        XCTAssertEqual(ns.domain, "MLNErrorDomain", "tiles-only failure domain")
        XCTAssertEqual(ns.code, 6, "tiles-only failure code")
    }

    /// Terrain-only failure (vector tiles, sprite and glyphs reachable, terrain
    /// tiles not). VERIFIED 2026-09-18: MLNMapSnapshotter errors even when only
    /// the raster-dem source is unreachable. This means a terrain host failure
    /// blocks the film — the same path as vector tile failure.
    func testUnreachableTerrainOnlyAlsoReturnsAnError() async throws {
        let styleURL = try styleWithUnresolvableHost(replacing: .terrainOnly)
        let error = try await snapshotError(styleURL: styleURL)
        let ns = error as NSError
        print("terrain-only: domain=\(ns.domain) code=\(ns.code)")
    }

    // MARK: - Helpers

    private enum ReplacementScope {
        case all, vectorOnly, terrainOnly
    }

    private func snapshotResult(styleURL: URL) async throws -> Result<MLNMapSnapshot, Error> {
        let center = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
        let camera = MLNMapCamera()
        camera.centerCoordinate = center
        camera.pitch = 0
        camera.heading = 0
        let options = MLNMapSnapshotOptions(
            styleURL: styleURL, camera: camera, size: CGSize(width: 64, height: 64)
        )
        options.zoomLevel = 10
        options.scale = 1

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let snapshotter = MLNMapSnapshotter(options: options)
                snapshotter.start { snapshot, error in
                    _ = snapshotter
                    if let snapshot {
                        continuation.resume(returning: .success(snapshot))
                    } else {
                        continuation.resume(returning: .failure(error ?? MapLibreSnapshotProvider.SnapshotError()))
                    }
                }
            }
        }
    }

    private func snapshotError(styleURL: URL) async throws -> Error {
        let result = try await snapshotResult(styleURL: styleURL)
        switch result {
        case .failure(let error):
            return error
        case .success(let snapshot):
            guard let cgImage = snapshot.image.cgImage else {
                throw MapLibreSnapshotProvider.SnapshotError()
            }
            let isBlank = Self.isEffectivelyBlank(cgImage)
            XCTFail(
                "MLNMapSnapshotter returned a 'successful' image with unreachable tiles "
                + "(blank=\(isBlank), \(cgImage.width)×\(cgImage.height)). "
                + "Detection logic is needed in MapLibreSnapshotProvider."
            )
            throw MapLibreSnapshotProvider.SnapshotError()
        }
    }

    private func styleWithUnresolvableHost(replacingAll: Bool) throws -> URL {
        try styleWithUnresolvableHost(replacing: replacingAll ? .all : .vectorOnly)
    }

    private func styleWithUnresolvableHost(replacing scope: ReplacementScope) throws -> URL {
        let resource = "openfreemap-liberty-dark"
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: resource, withExtension: "json"),
            "\(resource).json must be bundled"
        )
        var json = try String(contentsOf: url, encoding: .utf8)
        switch scope {
        case .all:
            json = json.replacingOccurrences(
                of: "tiles.openfreemap.org",
                with: "tiles.unresolvable.invalid"
            )
            json = json.replacingOccurrences(
                of: "s3.amazonaws.com",
                with: "s3.unresolvable.invalid"
            )
        case .vectorOnly:
            json = json.replacingOccurrences(
                of: "\"https://tiles.openfreemap.org/planet\"",
                with: "\"https://tiles.unresolvable.invalid/planet\""
            )
        case .terrainOnly:
            json = json.replacingOccurrences(
                of: "s3.amazonaws.com/elevation-tiles-prod",
                with: "s3.unresolvable.invalid/elevation-tiles-prod"
            )
        }
        let suffix: String
        switch scope {
        case .all: suffix = "all"
        case .vectorOnly: suffix = "tiles-only"
        case .terrainOnly: suffix = "terrain-only"
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-test-unreachable-\(suffix).json")
        try json.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    private static func isEffectivelyBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return true }
        let count = CFDataGetLength(data)
        for offset in stride(from: 0, to: min(count, 4096), by: 4) where bytes[offset + 3] != 0 {
            return false
        }
        return true
    }
}
#endif

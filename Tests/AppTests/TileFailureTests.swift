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
    /// DNS failure must surface as an error, not a blank image.
    func testUnreachableTileHostReturnsAnError() async throws {
        let styleURL = try styleWithUnresolvableHost()
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

        let result: Result<MLNMapSnapshot, Error> = await withCheckedContinuation { continuation in
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

        switch result {
        case .failure:
            break
        case .success(let snapshot):
            guard let cgImage = snapshot.image.cgImage else {
                return
            }
            let isBlank = Self.isEffectivelyBlank(cgImage)
            XCTFail(
                "MLNMapSnapshotter returned a 'successful' image with unreachable tiles "
                + "(blank=\(isBlank), \(cgImage.width)×\(cgImage.height)). "
                + "Detection logic is needed in MapLibreSnapshotProvider."
            )
        }
    }

    // MARK: - Helpers

    private func styleWithUnresolvableHost() throws -> URL {
        let resource = "openfreemap-liberty-dark"
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: resource, withExtension: "json"),
            "\(resource).json must be bundled"
        )
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(
            of: "tiles.openfreemap.org",
            with: "tiles.unresolvable.invalid"
        )
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-test-unreachable-style.json")
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

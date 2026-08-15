@testable import Kamome
import KamomeImportKit
import XCTest

/// Trip fixtures for the demo renders: `Tests/Fixtures/trips/*.json`, one per
/// dogfood region. Data rather than literals so a render is a fixture swap, and
/// so a real photo library can be dumped into the same shape
/// (`Tools/exif-to-fixture.sh`).
extension RecapDemoFilmTests {
    /// **A local dump of the same name wins** (privacy principle, CLAUDE.md §0).
    ///
    /// `Tools/exif-to-fixture.sh` writes real trips to `Fixtures/trips/local/`,
    /// which is gitignored, so `iceland` means *your* photographs at the desk and
    /// the committed synthetic placeholder in CI. Neither the harnesses nor the
    /// gates need to know which they got — that is the point. Real coordinates are
    /// a record of where a person was, and they never enter the repository.
    static func tripFixture(named name: String) throws -> (title: String, photos: [ImportPhoto]) {
        let trips = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/trips")
        let local = trips.appendingPathComponent("local/\(name).json")
        let url = FileManager.default.fileExists(atPath: local.path)
            ? local
            : trips.appendingPathComponent("\(name).json")
        if url == local { print("KAMOME_FIXTURE \(name): using the local dump (not committed)") }
        let fixture = try JSONDecoder().decode(TripFixture.self, from: try Data(contentsOf: url))
        // Fixture times are offsets from the trip start, so a fixture reads as a
        // day rather than as a wall-clock date nobody can check.
        let start = 1_752_600_000.0
        return (
            fixture.title,
            fixture.photos.map {
                ImportPhoto(assetId: $0.id, timestamp: start + $0.offsetS, lat: $0.lat, lon: $0.lon)
            }
        )
    }
}

/// On-disk shape of `Tests/Fixtures/trips/*.json` — place and time only, which
/// is exactly what `ImportService` sees on device.
private struct TripFixture: Decodable {
    struct Photo: Decodable {
        let id: String
        /// Seconds from the trip's first photo.
        let offsetS: Double
        let lat: Double
        let lon: Double

        enum CodingKeys: String, CodingKey {
            case id, lat, lon
            case offsetS = "t"
        }
    }

    let title: String
    let photos: [Photo]
}

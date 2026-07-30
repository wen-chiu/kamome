@testable import Kamome
import KamomeImportKit
import XCTest

/// Trip fixtures for the demo renders: `Tests/Fixtures/trips/*.json`, one per
/// dogfood region. Data rather than literals so a render is a fixture swap, and
/// so a real photo library can be dumped into the same shape
/// (`Tools/exif-to-fixture.sh`).
extension RecapDemoFilmTests {
    static func tripFixture(named name: String) throws -> (title: String, photos: [ImportPhoto]) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/trips/\(name).json")
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

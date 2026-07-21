@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// Photo-EXIF import end-to-end (spec §4.7, Replay MVP handoff §1): synthetic
/// geotagged photos → `ImportService` → an `imported_photos` trip that flows
/// through `RecapComposer` unchanged. Fast and deterministic (in-memory DB, no
/// PhotoKit, no network — `matching.base_url` ships "" so snapping is a no-op),
/// so it runs in CI as the "imported trip is first-class" gate.
final class ImportPipelineE2ETests: XCTestCase {
    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    func testImportedTripFlowsThroughRecapComposer() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)

        // Two well-separated stops (each ≥ minPhotosPerStop) + a lone route photo.
        let photos = [
            photo("a1", 0, 64.264, -20.516),
            photo("a2", 120, 64.265, -20.515),
            photo("a3", 240, 64.263, -20.517),
            photo("lone", 3_600, 63.900, -19.800),
            photo("b1", 7_200, 63.404, -19.041),
            photo("b2", 7_320, 63.405, -19.040)
        ]

        let tripId = try await service.importTrip(title: "Iceland Ring Road", photos: photos)

        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.trip.tripSource, .importedPhotos, "provenance is honest, never 'recorded'")
        XCTAssertTrue(detail.trip.tripSource.isReconstructed)
        XCTAssertEqual(detail.segments.count, 1)
        XCTAssertEqual(detail.segments[0].segment.segmentSource, .exif)
        XCTAssertEqual(detail.stops.count, 2)

        // The whole point: an imported trip is first-class — RecapComposer maps
        // it into recap inputs with no special-casing.
        let route = RecapComposer.route(
            from: detail.segments,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        XCTAssertGreaterThanOrEqual(route.count, 2)
        let content = RecapComposer.content(
            trip: detail.trip,
            route: route,
            stops: detail.stops,
            stats: nil,
            photosByStop: [:]
        )
        XCTAssertNotNil(content, "imported trip must produce recap content unchanged")
        XCTAssertEqual(content?.stops.count, 2)
    }

    func testTooFewGeotaggedPhotosIsRejected() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)

        do {
            _ = try await service.importTrip(title: "Nope", photos: [photo("only", 0, 10, 10)])
            XCTFail("a single photo is not a trip")
        } catch {
            XCTAssertEqual(error as? ImportService.ImportError, .notEnoughGeotaggedPhotos)
        }
    }
}

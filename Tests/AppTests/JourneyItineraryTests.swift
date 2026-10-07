@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine
import XCTest

/// **A found journey's itinerary is the trip it would become** (Footprints ADR
/// draft 2026-09-30, Data 1 and "Tests owed"). The preview is drawn from the
/// cluster plan and nothing is stored; 「新增旅程」 stores that plan. If the
/// two disagreed, the diary would preview one journey and S3 would open another.
@MainActor
final class JourneyItineraryTests: XCTestCase {
    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// Invented places. Two stops a day apart and a third two days later, with
    /// one photograph taken on the road between the first two.
    private func journey() -> [ImportPhoto] {
        let start = 1_780_000_000.0
        var photos = (0..<8).map { photo("a-\($0)", start + Double($0) * 600, 35.68, 139.65) }
        photos.append(photo("road-0", start + 30_000, 35.30, 138.90))
        photos += (0..<6).map { photo("b-\($0)", start + 86_400 + Double($0) * 600, 35.01, 135.77) }
        photos += (0..<5).map { photo("c-\($0)", start + 3 * 86_400 + Double($0) * 600, 34.69, 135.50) }
        return photos
    }

    private func config() throws -> TrackingConfig {
        try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0)
    }

    /// What a reader sees of a place: everything but the id, which is the
    /// plan's position before it is stored and the stop's id after.
    private struct Seen: Equatable {
        let lat: Double, lon: Double, arrivedAt: Double, departedAt: Double?
        let name: String?, photos: [String]
        init(_ place: JourneyItinerary.Place) {
            (lat, lon, arrivedAt, departedAt) = (place.lat, place.lon, place.arrivedAt, place.departedAt)
            (name, photos) = (place.name, place.photoAssetIds)
        }
    }

    func testAPreviewsItineraryIsTheImportedTripsItinerary() async throws {
        let config = try config()
        let photos = journey()
        let plan = PhotoImportClusterer.plan(photos: photos, config: ImportService.clustering(config))
        let preview = JourneyItinerary(plan: plan, photos: photos, config: config)

        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: nil, photos: photos, plan: plan)
        let stored = JourneyItinerary(detail: try XCTUnwrap(repository.detail(tripId: tripId)))

        XCTAssertEqual(preview.places.count, 3, "the fixture's three stops")
        XCTAssertEqual(preview.places.map(Seen.init), stored.places.map(Seen.init), "the same places, times and photographs")
        XCTAssertEqual(preview.days.map(\.index), stored.days.map(\.index), "on the same days")
        XCTAssertEqual(
            preview.days.flatMap { $0.entries.map(\.leg) }, stored.days.flatMap { $0.entries.map(\.leg) },
            "the same travel between them, inferred until routing answers"
        )
        XCTAssertEqual(preview.routePhotoAssetIds, stored.routePhotoAssetIds)
        XCTAssertEqual(preview.routePhotoAssetIds, ["road-0"])
        XCTAssertEqual(preview.photoCount, photos.count)
        XCTAssertEqual(preview.dayCount, stored.dayCount)
        XCTAssertFalse(preview.isStored)
        XCTAssertEqual(stored.tripId, tripId)
    }

    /// **A flown leg is flown in the preview too** (#224 meets Footprints). The
    /// import stores a leg a photograph was taken in flight on as a crossing,
    /// so the preview must draw it as one, or the found journey shows a road
    /// where the trip it becomes shows a plane. Public landmarks only (§0):
    /// the fixture of `ImportFlownLegTests`.
    func testAFlownLegIsACrossingInThePreviewAsInTheStoredTrip() async throws {
        let config = try config()
        let hour = 3600.0
        func photo(_ id: String, _ hours: Double, _ lat: Double, _ lon: Double, altitude: Double = 50) -> ImportPhoto {
            ImportPhoto(assetId: id, timestamp: hours * hour, lat: lat, lon: lon, altitudeLowerBoundM: altitude)
        }
        let photos = [
            photo("la1", 0, 34.0522, -118.2437), photo("la2", 0.2, 34.0522, -118.2437),
            photo("window", 3, 38.5, -98.0, altitude: 10_500),
            photo("ny1", 30, 40.7128, -74.0060), photo("ny2", 30.2, 40.7128, -74.0060),
            photo("bos1", 36, 42.3601, -71.0589), photo("bos2", 36.2, 42.3601, -71.0589)
        ]
        let plan = PhotoImportClusterer.plan(photos: photos, config: ImportService.clustering(config))
        let preview = JourneyItinerary(plan: plan, photos: photos, config: config)

        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: nil, photos: photos, plan: plan)
        let stored = JourneyItinerary(detail: try XCTUnwrap(repository.detail(tripId: tripId)))

        let previewLegs = preview.days.flatMap { $0.entries.compactMap(\.leg) }
        XCTAssertEqual(previewLegs.map(\.isCrossing), [true, false], "Los Angeles → New York flown, the drive to Boston not")
        XCTAssertEqual(previewLegs, stored.days.flatMap { $0.entries.compactMap(\.leg) })
    }

    /// For a stored trip, the stored version wins: an edit made in S3 is what
    /// Footprints shows.
    func testAStoredTripsItineraryShowsItsEdits() async throws {
        let config = try config()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: nil, photos: journey())
        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        let second = detail.stops[1]
        try repository.setStopName(stopId: second.id, name: "Edited")

        let itinerary = JourneyItinerary(detail: try XCTUnwrap(repository.detail(tripId: tripId)))
        XCTAssertEqual(itinerary.places.map(\.name), [nil, "Edited", nil])
        XCTAssertEqual(itinerary.places.map(\.id), detail.stops.map(\.id))
    }

    /// The first place has no travel into it; every later one does.
    func testTheFirstPlaceHasNoLegIntoIt() throws {
        let config = try config()
        let photos = journey()
        let plan = PhotoImportClusterer.plan(photos: photos, config: ImportService.clustering(config))
        let entries = JourneyItinerary(plan: plan, photos: photos, config: config).days.flatMap(\.entries)
        XCTAssertNil(entries.first?.leg)
        XCTAssertTrue(entries.dropFirst().allSatisfy { $0.leg?.provenance == .inferred })
    }

    // MARK: - The folding rule S3 and the itinerary share

    private func piece(_ at: Double, _ mode: TransportMode, _ claim: RouteProvenance, crossing: Bool = false)
        -> StoryLegFolding.Piece {
        StoryLegFolding.Piece(startedAt: at, mode: mode, provenance: claim, isCrossing: crossing)
    }

    func testALegIsAsHonestAsItsLeastKnownStretch() throws {
        let folded = try XCTUnwrap(StoryLegFolding.fold([
            piece(10, .drive, .recorded), piece(20, .drive, .reconstructed), piece(30, .walk, .recorded)
        ], from: 0, to: 40))
        XCTAssertEqual(folded.modes, [.drive, .walk], "consecutive repeats fold into one")
        XCTAssertEqual(folded.provenance, .reconstructed)

        let inferred = try XCTUnwrap(StoryLegFolding.fold([
            piece(10, .drive, .inferred), piece(20, .drive, .reconstructed)
        ], from: 0, to: 40))
        XCTAssertEqual(inferred.provenance, .inferred)
    }

    func testOnlyPiecesStartingInTheGapCount() throws {
        let pieces = [piece(5, .drive, .recorded), piece(50, .walk, .inferred, crossing: true)]
        let folded = try XCTUnwrap(StoryLegFolding.fold(pieces, from: 0, to: 40))
        XCTAssertEqual(folded.modes, [.drive])
        XCTAssertFalse(folded.isCrossing)
        XCTAssertNil(StoryLegFolding.fold(pieces, from: 60, to: 90))
    }
}

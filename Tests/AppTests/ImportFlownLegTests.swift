import CoreLocation
@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import XCTest

/// **A leg a photograph was taken in flight on is stored as flown at import**
/// (#224, ADR 2026-10-06) — before routing, and whatever the clocks say. The
/// flight here has a night either side, so neither `LegPace` nor
/// `RouteFeasibility`'s time test could call it.
final class ImportFlownLegTests: XCTestCase {
    /// Counts the legs that reach routing, and answers each with a road.
    private actor CountingReconstructor: RouteReconstructing {
        private(set) var calls = 0

        func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
            calls += 1
            return .implausible
        }
    }

    private struct UnusedMatcher: RouteMatchProviding {
        func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? { nil }
    }

    private let hour = 3600.0
    // Public landmarks only (§0) — synthetic geometry, never a real trip.
    private let losAngeles = (lat: 34.0522, lon: -118.2437)
    private let overKansas = (lat: 38.5000, lon: -98.0000)
    private let newYork = (lat: 40.7128, lon: -74.0060)
    private let boston = (lat: 42.3601, lon: -71.0589)

    private func photo(
        _ id: String, _ hours: Double, _ place: (lat: Double, lon: Double), altitude: Double? = 50
    ) -> ImportPhoto {
        ImportPhoto(
            assetId: id, timestamp: hours * hour, lat: place.lat, lon: place.lon, altitudeLowerBoundM: altitude
        )
    }

    /// Los Angeles, a window photograph at cruise, New York thirty hours after
    /// the last photo in Los Angeles, then a drive to Boston.
    private func photos(window: Double?) -> [ImportPhoto] {
        [
            photo("la1", 0, losAngeles), photo("la2", 0.2, losAngeles),
            photo("window", 3, overKansas, altitude: window),
            photo("ny1", 30, newYork), photo("ny2", 30.2, newYork),
            photo("bos1", 36, boston), photo("bos2", 36.2, boston)
        ]
    }

    func testTheLegAWindowPhotoSitsOnIsFlownAndNeverRouted() async throws {
        let (repository, tripId) = try await importTrip(window: 10_500)

        let segments = try XCTUnwrap(repository.detail(tripId: tripId)).segments.map(\.segment)
        XCTAssertEqual(segments.count, 2, "Los Angeles → New York, New York → Boston")
        XCTAssertEqual(segments[0].routeVerdict, .beyondDriving)
        XCTAssertTrue(RecapComposer.isCrossing(segments[0]), "the plane flies it")
        XCTAssertNil(segments[1].routeVerdict, "the drive to Boston is untouched")

        let reconstructor = CountingReconstructor()
        let report = await RouteMatchService(
            repository: repository,
            matching: AppConfig.loadOrDie().matching.withBaseURL("https://routing.invalid"),
            provider: UnusedMatcher(), reconstructor: reconstructor
        ).matchTrip(tripId: tripId)
        let calls = await reconstructor.calls
        XCTAssertEqual(calls, 1, "only the drive is asked about — the airborne fix stays on the phone")
        XCTAssertEqual(report.beyondDriving, 1)
    }

    /// Without the window photograph's altitude nothing is claimed at import.
    func testWithoutAnAltitudeNothingIsClaimed() async throws {
        let (repository, tripId) = try await importTrip(window: nil)

        let segments = try XCTUnwrap(repository.detail(tripId: tripId)).segments.map(\.segment)
        XCTAssertNil(segments[0].routeVerdict)
    }

    /// Two window photographs seconds apart cluster into a stop in the sky; its
    /// first and last photographs end both of its legs, so both are flown.
    func testAStopOfWindowPhotosFliesBothItsLegs() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config).importTrip(title: nil, photos: [
            photo("la1", 0, losAngeles), photo("la2", 0.2, losAngeles),
            photo("w1", 3, overKansas, altitude: 10_500), photo("w2", 3.001, overKansas, altitude: 10_500),
            photo("ny1", 30, newYork), photo("ny2", 30.2, newYork)
        ])

        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops.count, 3, "precondition: the window photographs made a stop")
        XCTAssertEqual(detail.segments.map(\.segment.routeVerdict), [.beyondDriving, .beyondDriving])
    }

    // MARK: - Reading the fix

    func testAnInvalidAltitudeIsNoAltitude() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 10_000,
            horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: .now
        )
        XCTAssertNil(PhotoLibraryImportSource.altitudeLowerBoundM(location))
    }

    func testTheAltitudeIsReadLowByItsAccuracy() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 10_000,
            horizontalAccuracy: 10, verticalAccuracy: 30, timestamp: .now
        )
        XCTAssertEqual(PhotoLibraryImportSource.altitudeLowerBoundM(location), 9_970)
    }

    func testTheSpeedIsReadLowByItsAccuracyAndInvalidSpeedIsNone() {
        func location(speed: Double, accuracy: Double) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 0,
                horizontalAccuracy: 10, verticalAccuracy: 10, course: 0, courseAccuracy: 5,
                speed: speed, speedAccuracy: accuracy, timestamp: .now
            )
        }
        XCTAssertEqual(
            try XCTUnwrap(PhotoLibraryImportSource.speedLowerBoundKmh(location(speed: 250, accuracy: 5))), 882,
            accuracy: 0.001
        )
        XCTAssertNil(PhotoLibraryImportSource.speedLowerBoundKmh(location(speed: -1, accuracy: 5)))
        XCTAssertNil(PhotoLibraryImportSource.speedLowerBoundKmh(location(speed: 250, accuracy: -1)))
    }

    // MARK: - Fixtures

    private func importTrip(window: Double?) async throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: AppConfig.loadOrDie())
            .importTrip(title: nil, photos: photos(window: window))
        return (repository, tripId)
    }
}

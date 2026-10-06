@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **A road the router found is stored only if someone could have driven it**
/// (ADR 2026-10-03). A flight between two airports on one continent was
/// answered with a real road, passed the detour gate, and the film drew a drive
/// nobody drove — the verdict that makes it a crossing, or at least
/// dashed, has to be written where the film will read it.
final class RouteMatchFeasibilityTests: XCTestCase {
    /// Answers every leg with the same overland road, the way the router
    /// answers a flight across connected land.
    private struct OverlandReconstructor: RouteReconstructing {
        let road: [GeoPoint]

        func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
            .routed(RouteMatchOutcome(geometry: road, confidence: 1))
        }
    }

    private struct UnusedMatcher: RouteMatchProviding {
        func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? { nil }
    }

    private let start = 1_780_000_000.0
    // Public landmarks only (§0) — synthetic geometry, never a real trip.
    private let laxAirport = (lat: 33.9416, lon: -118.4085)
    private let denver = (lat: 39.7392, lon: -104.9903)
    private let chicago = (lat: 41.8781, lon: -87.6298)
    private let jfkAirport = (lat: 40.6413, lon: -73.7781)

    private var overland: [GeoPoint] {
        [laxAirport, denver, chicago, jfkAirport].map { GeoPoint(lat: $0.lat, lon: $0.lon) }
    }

    /// Twenty-six hours between the last photograph before the flight and the
    /// first after landing: too slow for the straight-line pace, too fast for
    /// the road.
    func testARoadNobodyCouldDriveInTheTimeIsStoredAsACrossing() async throws {
        let (repository, tripId) = try seed(hours: 26)

        let report = await service(repository).matchTrip(tripId: tripId)

        XCTAssertEqual(report.beyondDriving, 0, "precondition: the straight-line pace did not call it")
        XCTAssertEqual(report.routedButNotDriven, 1)
        XCTAssertEqual(report.reconstructed, 0)
        let flight = try XCTUnwrap(repository.detail(tripId: tripId)).segments[0].segment
        XCTAssertNil(flight.matchedPolyline, "the overland road is never stored")
        XCTAssertEqual(flight.routeVerdict, .beyondDriving)
        XCTAssertTrue(RecapComposer.isCrossing(flight), "the plane flies it")
    }

    /// Sixty hours: the road fits the time, but nothing along it says anyone
    /// drove it. Dashed — never a road, and never a plane either.
    func testAnUnwitnessedRoadIsRefusedButNotFlown() async throws {
        let (repository, tripId) = try seed(hours: 60)

        let report = await service(repository).matchTrip(tripId: tripId)

        XCTAssertEqual(report.implausibleRoute, 1)
        XCTAssertEqual(report.reconstructed, 0)
        let flight = try XCTUnwrap(repository.detail(tripId: tripId)).segments[0].segment
        XCTAssertNil(flight.matchedPolyline)
        XCTAssertEqual(flight.routeVerdict, .implausibleRoute)
        XCTAssertFalse(RecapComposer.isCrossing(flight))
        XCTAssertEqual(RecapComposer.provenance(for: flight), .inferred, "drawn dashed")
    }

    // MARK: - Fixtures

    private func service(_ repository: TripRepository) -> RouteMatchService {
        RouteMatchService(
            repository: repository,
            matching: AppConfig.loadOrDie().matching.withBaseURL("https://routing.invalid"),
            provider: UnusedMatcher(), reconstructor: OverlandReconstructor(road: overland)
        )
    }

    /// One imported leg, airport to airport, with only its two photographs.
    private func seed(hours: Double) throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let end = start + hours * 3600
        let tripId = try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: "Feasibility", startedAt: start, endedAt: end,
                source: TripSource.importedPhotos.rawValue,
                segments: [
                    TripRepository.NewSegment(
                        mode: TransportMode.drive.rawValue, startedAt: start, endedAt: end,
                        points: [
                            TripRepository.NewTrackpoint(ts: start, lat: laxAirport.lat, lon: laxAirport.lon),
                            TripRepository.NewTrackpoint(ts: end, lat: jfkAirport.lat, lon: jfkAirport.lon)
                        ],
                        source: SegmentSource.exif.rawValue
                    )
                ],
                stopsWithPhotos: [], routeAttachedPhotos: []
            )
        )
        return (repository, tripId)
    }
}

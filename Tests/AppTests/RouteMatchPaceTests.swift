@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **A leg too fast to drive is a crossing, and routing is never asked about
/// it** (ADR 2026-09-24 (c)). The Vietnam film opened on a scooter riding a
/// dashed line over the Taiwan Strait because only routing could call a leg a
/// crossing, and routing never said "no road" (`Docs/handoff-vietnam-crossing.md`).
final class RouteMatchPaceTests: XCTestCase {
    /// Counts the legs that reached it. Any leg that does is told "a road
    /// exists", so a leg that still ends up a crossing got there by pace alone.
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

    private let start = 1_780_000_000.0
    // Public landmarks only (§0).
    private let taoyuanAirport = (lat: 25.0777, lon: 121.2328)
    private let noiBaiAirport = (lat: 21.2187, lon: 105.8042)
    private let hanoiOldQuarter = (lat: 21.0340, lon: 105.8500)

    func testAFlightIsACrossingAndIsNeverSentToRouting() async throws {
        let (repository, tripId) = try seed()
        let reconstructor = CountingReconstructor()

        let report = await service(repository, reconstructor).matchTrip(tripId: tripId)

        let calls = await reconstructor.calls
        XCTAssertEqual(calls, 1, "only the drive into town is asked about — the flight's ends stay on the phone")
        XCTAssertEqual(report.beyondDriving, 1)
        let segments = try XCTUnwrap(repository.detail(tripId: tripId)).segments.map(\.segment)
        XCTAssertEqual(segments[0].routeVerdict, .beyondDriving)
        XCTAssertTrue(RecapComposer.isCrossing(segments[0]), "the plane flies it")
        XCTAssertFalse(RecapComposer.isCrossing(segments[1]), "the drive into town is still a drive")
    }

    /// A leg a road router already answered about — as the Vietnam film's
    /// opening leg may have been — is re-judged, not left dashed forever.
    func testAStoredRoadRouterAnswerOnAFlightIsReplaced() async throws {
        let (repository, tripId) = try seed()
        let flight = try XCTUnwrap(repository.detail(tripId: tripId)).segments[0].segment
        try repository.setRoutability(segmentId: flight.id, .offRoadNetwork)

        _ = await service(repository, CountingReconstructor()).matchTrip(tripId: tripId)

        let judged = try XCTUnwrap(repository.detail(tripId: tripId)).segments[0].segment
        XCTAssertEqual(judged.routeVerdict, .beyondDriving)
    }

    /// Needs no network: routing switched off still flies the plane.
    func testThePaceIsJudgedWithRoutingDisabled() async throws {
        let (repository, tripId) = try seed()
        let disabled = RouteMatchService(
            repository: repository, matching: AppConfig.loadOrDie().matching.withBaseURL("")
        )

        let report = await disabled.matchTrip(tripId: tripId)

        XCTAssertTrue(report.isDisabled)
        XCTAssertEqual(report.beyondDriving, 1)
    }

    // MARK: - Fixtures

    private func service(_ repository: TripRepository, _ reconstructor: CountingReconstructor) -> RouteMatchService {
        RouteMatchService(
            repository: repository,
            matching: AppConfig.loadOrDie().matching.withBaseURL("https://routing.invalid"),
            provider: UnusedMatcher(), reconstructor: reconstructor
        )
    }

    /// Taoyuan airport to Noi Bai in five hours, then an hour's drive into town.
    private func seed() throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        func leg(
            _ from: (lat: Double, lon: Double), _ to: (lat: Double, lon: Double), at hours: Double, for span: Double
        ) -> TripRepository.NewSegment {
            let begin = start + hours * 3600, end = begin + span * 3600
            return TripRepository.NewSegment(
                mode: TransportMode.drive.rawValue, startedAt: begin, endedAt: end,
                points: [
                    TripRepository.NewTrackpoint(ts: begin, lat: from.lat, lon: from.lon),
                    TripRepository.NewTrackpoint(ts: end, lat: to.lat, lon: to.lon)
                ],
                source: SegmentSource.exif.rawValue
            )
        }
        let tripId = try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: "Pace", startedAt: start, endedAt: start + 6 * 3600,
                source: TripSource.importedPhotos.rawValue,
                segments: [
                    leg(taoyuanAirport, noiBaiAirport, at: 0, for: 5),
                    leg(noiBaiAirport, hanoiOldQuarter, at: 5, for: 1)
                ],
                stopsWithPhotos: [], routeAttachedPhotos: []
            )
        )
        return (repository, tripId)
    }
}

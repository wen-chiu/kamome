@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **A route of one point is answered once, not on every export** (#256).
///
/// On the #112 phone run, three legs of a photo trip came back from routing as
/// a route of one point. That was read as an answer nobody could read, which
/// stores no verdict, so every export of the trip asked for those legs again
/// and spent three requests of the users' shared daily quota each time.
///
/// These run the real `GeoapifyRouteProvider` against a stubbed transport, so
/// the whole path is under test: the wire answer, the verdict it becomes, what
/// is stored, and whether the next export sends anything.
final class RouteMatchOnePointTests: XCTestCase {
    /// Counts what reached the network.
    private actor Requests {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private struct UnusedMatcher: RouteMatchProviding {
        func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? { nil }
    }

    private let start = 1_780_000_000.0
    // Synthetic places (§0) — round numbers, never a real trip.
    private let carPark = (lat: 40.0, lon: -100.0)
    /// About 150 m north of `carPark`.
    private let viewpoint = (lat: 40.00135, lon: -100.0)

    /// The answer the phone logged as `the provider returned 1 points`: one
    /// part whose two ends are the same place, which the client reads as a
    /// single point. INFERRED wire shape — both photographs snapping to one
    /// road point; the log line added for #256 measures it on the next run.
    private var onePointRoute: Data {
        routeBody(parts: [[[carPark.lon, carPark.lat], [carPark.lon, carPark.lat]]])
    }

    func testASecondExportSendsNothingForALegAnsweredWithOnePoint() async throws {
        let (repository, tripId) = try seed()
        let requests = Requests()
        let service = service(repository, requests: requests, answer: onePointRoute)

        let first = await service.matchTrip(tripId: tripId)
        let second = await service.matchTrip(tripId: tripId)

        let sent = await requests.count
        XCTAssertEqual(sent, 1, "the second export must not ask routing again for a leg it already answered")
        XCTAssertEqual(second, first, "the second export reports what the first established, from storage")

        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        let leg = detail.segments[0].segment
        XCTAssertEqual(leg.routeVerdict, .implausibleRoute, "a road is near, and this route is not the leg's way")
        XCTAssertNil(leg.matchedPolyline, "a point is never stored as the leg's road")
        XCTAssertEqual(RecapComposer.provenance(for: leg), .inferred, "still drawn dashed, never as a road")
        XCTAssertFalse(RecapComposer.isCrossing(leg), "and never flown")
        XCTAssertTrue(
            RecapComposer.everyLegRoutabilityEstablished(detail.segments),
            "the film type no longer waits on this leg"
        )
    }

    /// The fix is narrow: a 200 with no route in it says nothing about the
    /// ground, so it stays unanswered and the next export asks again.
    func testAnAnswerWithNoRouteInItIsStillAskedAgain() async throws {
        let (repository, tripId) = try seed()
        let requests = Requests()
        // swiftlint:disable:next force_try
        let empty = try! JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": []])
        let service = service(repository, requests: requests, answer: empty)

        let first = await service.matchTrip(tripId: tripId)
        _ = await service.matchTrip(tripId: tripId)

        let sent = await requests.count
        XCTAssertEqual(first.notEstablished, 1)
        XCTAssertEqual(sent, 2, "nothing was learnt, so the next export asks again")
        XCTAssertNil(try XCTUnwrap(repository.detail(tripId: tripId)).segments[0].segment.routeVerdict)
    }

    // MARK: - Fixtures

    private func routeBody(parts: [[[Double]]]) -> Data {
        let json: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": ["distance": 0, "distance_units": "meters", "mode": "drive"],
                "geometry": ["type": "MultiLineString", "coordinates": parts]
            ]]
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func service(_ repository: TripRepository, requests: Requests, answer: Data) -> RouteMatchService {
        let matching = AppConfig.loadOrDie().matching.withBaseURL("https://routing.invalid")
        let provider = GeoapifyRouteProvider(config: matching) { request in
            await requests.record()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (answer, response)
        }
        return RouteMatchService(
            repository: repository, matching: matching, provider: UnusedMatcher(), reconstructor: provider
        )
    }

    /// One imported drive leg between two photographs twenty minutes apart.
    private func seed() throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let end = start + 20 * 60
        let tripId = try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: "One point", startedAt: start, endedAt: end,
                source: TripSource.importedPhotos.rawValue,
                segments: [
                    TripRepository.NewSegment(
                        mode: TransportMode.drive.rawValue, startedAt: start, endedAt: end,
                        points: [
                            TripRepository.NewTrackpoint(ts: start, lat: carPark.lat, lon: carPark.lon),
                            TripRepository.NewTrackpoint(ts: end, lat: viewpoint.lat, lon: viewpoint.lon)
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

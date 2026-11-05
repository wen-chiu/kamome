@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **A film opens at the trip's first stop, never at a place before it** (#362).
///
/// Chiu's short film of a photo-imported trip, 2026-11-03: the car waited on
/// open water, a dashed line ran from there into the first stop (an airport),
/// and the road began at the airport. His photographs do not reproduce it at the
/// desk. Synthetic trips put the car there in one shape that is fixed: a point
/// stored *before* the first stop, such as a photograph from the aircraft on
/// the approach, alone or as a stop that was then deleted. Its leg into the
/// airport was drawn. `TripRoute` (#348, ADR 2026-10-30) takes that leg off;
/// it merged an hour after the film was made.
///
/// These hold the whole way: import, routing, the edit, the composer and the
/// timeline, on both lengths. They fail with `TripRoute` passing every leg.
///
/// **Not held here:** a stop still stored before the first one, which the
/// short film drops. The film still opens there, and whether it should is
/// Chiu's question on #362.
@MainActor
final class FilmOpensAtTheFirstStopTests: XCTestCase {
    func testAStopBeforeTheFirstThatWasDeletedLeavesTheFilmOpeningAtTheFirstStop() async throws {
        let approach = RoutePathScenarios.visit("approach", Approach.water, hour: -0.4, count: 2)
        try await assertOpensAtTheAirport(photos: approach + Approach.trip()) { repository, detail in
            let first = try XCTUnwrap(detail.stops.first)
            XCTAssertLessThan(Approach.metres(first.lat, first.lon, Approach.water), 100, "the approach is the first stop")
            try repository.deleteStop(stopId: first.id)
        }
    }

    func testALoosePhotographBeforeTheFirstStopLeavesTheFilmOpeningAtTheFirstStop() async throws {
        let approach = RoutePathScenarios.visit("approach", Approach.water, hour: -0.4, count: 1)
        try await assertOpensAtTheAirport(photos: approach + Approach.trip())
    }

    private func assertOpensAtTheAirport(
        photos: [ImportPhoto],
        edit: (TripRepository, TripRepository.TripDetail) throws -> Void = { _, _ in },
        line: UInt = #line
    ) async throws {
        let config = try AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config).importTrip(title: nil, photos: photos)
        await RouteMatchService(
            repository: repository, matching: config.matching.withBaseURL("https://routing.invalid"),
            reconstructor: Approach()
        ).matchTrip(tripId: tripId)
        try edit(repository, try XCTUnwrap(repository.detail(tripId: tripId)))
        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        let firstStop = try XCTUnwrap(detail.stops.first)
        XCTAssertLessThan(Approach.metres(firstStop.lat, firstStop.lon, Approach.airport), 100,
                          "the airport is the first stored stop", line: line)

        for length in FilmLength.allCases {
            let trip = try XCTUnwrap(RecapComposer.filmComposition(
                detail: detail, config: config, photosEnabled: true, length: length
            )?.trip)
            let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config.export))
            let start = try XCTUnwrap(trip.route.first)
            let waiting = timeline.subjectState(atTime: 0)
            let setsOff = timeline.subjectState(atTime: timeline.journeyStartS)
            for (what, lat, lon) in [
                ("the trail", start.lat, start.lon),
                ("the car through the opening", waiting.lat, waiting.lon),
                ("the car as it sets off", setsOff.lat, setsOff.lon)
            ] {
                let away = Approach.metres(lat, lon, Approach.airport)
                XCTAssertLessThan(away, 100, "\(length): \(what) begins \(Int(away)) m from the first stop", line: line)
            }
        }
    }
}

/// The trip and its routing. Synthetic places on a made-up grid at the
/// equator (`CLAUDE.md` §0).
///
/// Routing answers as Geoapify does: a waypoint on the water is off the road
/// network, so that leg draws dashed, and every other leg gets a road.
private struct Approach: RouteReconstructing {
    typealias Place = RoutePathScenarios.Place

    static let airport = Place(lat: 0.10, lon: -30.10)
    static let nextTown = Place(lat: 0.40, lon: -29.80)
    /// Water between the two, where the approach photographs were taken.
    static let water = Place(lat: 0.25, lon: -29.95)

    /// Two stops of two photographs about 50 km apart, as on Chiu's trip, then
    /// the rest of a road trip. The short cut drops the first stop.
    static func trip() -> [ImportPhoto] {
        var photos = RoutePathScenarios.visit("airport", airport, hour: 0, count: 2)
            + RoutePathScenarios.visit("town", nextTown, hour: 1.74, count: 2)
            + RoutePathScenarios.visit("lake", Place(lat: 0.70, lon: -29.50), hour: 4.7, count: 18)
        for (index, hour) in [9.35, 19.5, 23.3, 25.0, 26.0, 27.4, 28.4, 32.3].enumerated() {
            let place = Place(lat: 0.80 + Double(index) * 0.12, lon: -29.40 + Double(index) * 0.15)
            photos += RoutePathScenarios.visit("stop\(index)", place, hour: hour, count: 3 + index % 4)
        }
        return photos
    }

    static func metres(_ lat: Double, _ lon: Double, _ place: Place) -> Double {
        Geo.distanceM(latA: lat, lonA: lon, latB: place.lat, lonB: place.lon)
    }

    func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
        if waypoints.contains(where: { Self.metres($0.lat, $0.lon, Self.water) < 3_000 }) {
            return .offTheRoadNetwork
        }
        return .routed(RouteMatchOutcome(geometry: RoutePathScenarios.Geography.road(through: waypoints), confidence: 1))
    }
}

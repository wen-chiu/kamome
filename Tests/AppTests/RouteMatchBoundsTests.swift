@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **Routing stops being able to hold the user** (2026-08-15).
///
/// The first person outside this project to install Kamome could not use it:
/// with a large photo library the app went unresponsive. `ImportService` awaited
/// `matchTrip` after the trip was already saved, `matchTrip` walked the legs one
/// at a time at `timeout_s` each, and the import sheet had disabled its own
/// Close button for the duration. More photographs meant more stops, more legs
/// and more back-to-back timeouts, behind a UI with nothing to press.
///
/// These are the bounds that replaced it: a per-trip budget, cooperative
/// cancellation, and four distinguishable outcomes instead of one silent
/// straight line.
final class RouteMatchBoundsTests: XCTestCase {
    // MARK: - Doubles

    /// A reconstructor that behaves however the failure under test needs, and
    /// counts how many legs actually reached it.
    private actor ScriptedReconstructor: RouteReconstructing {
        enum Behaviour {
            case succeed
            /// The provider answered: **no road** joins these places. Permanent,
            /// and the one verdict a crossing may be built on.
            case noRoute
            /// The provider answered with a route the detour gate refused. A
            /// road exists — dashed, never flown.
            case implausible
            /// Nobody answered, after burning `delayS` of the trip's budget.
            case unreachable(delayS: Double)
            case rateLimited
        }

        private let behaviour: Behaviour
        private(set) var calls = 0

        init(_ behaviour: Behaviour) {
            self.behaviour = behaviour
        }

        func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
            calls += 1
            switch behaviour {
            case .succeed:
                return .routed(RouteMatchOutcome(
                    geometry: waypoints.map { GeoPoint(lat: $0.lat, lon: $0.lon) }, confidence: 1
                ))
            case .noRoute:
                return .noRoadHere
            case .implausible:
                return .implausible
            case let .unreachable(delayS):
                try? await Task.sleep(nanoseconds: UInt64(delayS * 1_000_000_000))
                throw RouteProviderFailure.unreachable("stub: nothing answered")
            case .rateLimited:
                throw RouteProviderFailure.rateLimited(retryAfterS: 30)
            }
        }
    }

    private struct UnusedMatcher: RouteMatchProviding {
        func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? { nil }
    }

    // MARK: - The four outcomes

    /// The distinction the whole taxonomy exists for: a leg with genuinely no
    /// road route and a leg nobody could ask about produce the same dashed line
    /// in the film, and must not produce the same verdict.
    func testAProviderThatAnswersNoRouteIsNotTheSameAsOneThatNeverAnswers() async throws {
        let noRoute = try await report(legs: 3, behaviour: .noRoute)
        XCTAssertEqual(noRoute.noPlausibleRoute, 3)
        XCTAssertEqual(noRoute.unreachable, 0)
        XCTAssertEqual(noRoute.headline, .someLegsHaveNoRoad)

        // **Split apart on 2026-08-30**, because one of these two moves the
        // camera and the other must never be allowed to. Both still leave the
        // film with a dashed leg and both still say the same thing to the user;
        // what changed is that the counts no longer lie about which happened.
        let implausible = try await report(legs: 3, behaviour: .implausible)
        XCTAssertEqual(implausible.implausibleRoute, 3)
        XCTAssertEqual(
            implausible.noPlausibleRoute, 0,
            "a route the detour gate refused means a road exists — reading it as water would fly a plane over one"
        )
        XCTAssertEqual(implausible.headline, .someLegsHaveNoRoad)

        let unreachable = try await report(legs: 3, behaviour: .unreachable(delayS: 0))
        XCTAssertEqual(unreachable.unreachable, 3)
        XCTAssertEqual(unreachable.noPlausibleRoute, 0)
        XCTAssertEqual(unreachable.headline, .providerUnreachable)
    }

    /// A hosted provider will refuse for load; a LAN OSRM never did. "Wait and
    /// try again" is different advice from "check your connection".
    func testRateLimitingIsItsOwnVerdict() async throws {
        let limited = try await report(legs: 2, behaviour: .rateLimited)
        XCTAssertEqual(limited.rateLimited, 2)
        XCTAssertEqual(limited.unreachable, 0)
        XCTAssertEqual(limited.headline, .rateLimited)
    }

    /// A fully routed film has nothing to say, and neither does a disabled
    /// endpoint — the screen stays quiet unless there is something to act on.
    func testASuccessfulRunReportsNothingToTheUser() async throws {
        let routed = try await report(legs: 3, behaviour: .succeed)
        XCTAssertEqual(routed.reconstructed, 3)
        XCTAssertEqual(routed.headline, .allRouted)
        XCTAssertFalse(routed.isWorthReporting)
    }

    // MARK: - The bounds

    /// The P0's shape, bounded. Legs that time out one after another must stop
    /// consuming the user's afternoon; what is left draws dashed, which is a
    /// state the film already knows how to render (PD-2).
    func testTheTripBudgetStopsAWalkOfTimeouts() async throws {
        let reconstructor = ScriptedReconstructor(.unreachable(delayS: 0.2))
        // Room for roughly two legs out of six.
        let report = try await self.report(
            legs: 6, reconstructor: reconstructor, tripBudgetS: 0.35
        )

        let calls = await reconstructor.calls
        XCTAssertLessThan(calls, 6, "the budget must stop the run before every leg has timed out")
        XCTAssertGreaterThan(report.skipped, 0, "legs never asked about must be counted as skipped, not as no-road")
        XCTAssertEqual(report.attempted, 6)
        XCTAssertEqual(report.headline, .providerUnreachable, "what already failed outranks what was never tried")
    }

    /// Cancellation is checked per leg, the same shape `RecapExporter` uses for
    /// the render. A user who backs out is not made to wait for leg 39.
    func testCancellationStopsAtTheNextLeg() async throws {
        let reconstructor = ScriptedReconstructor(.succeed)
        var seen = 0
        let report = try await self.report(legs: 5, reconstructor: reconstructor) {
            seen += 1
            return seen <= 2
        }

        let calls = await reconstructor.calls
        XCTAssertEqual(calls, 2, "the third leg must never be requested")
        XCTAssertEqual(report.reconstructed, 2)
        XCTAssertEqual(report.skipped, 3)
        XCTAssertEqual(report.headline, .budgetExhausted, "cancelled legs are retryable, not unroutable")
    }

    /// Idempotence, which is what lets every call site fire freely: a second run
    /// finds the legs already matched and asks the provider nothing.
    func testASecondRunOverAMatchedTripAsksNothing() async throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try seed(legs: 3, into: repository)
        let reconstructor = ScriptedReconstructor(.succeed)
        let service = try makeService(repository: repository, reconstructor: reconstructor)

        _ = await service.matchTrip(tripId: tripId)
        let first = await reconstructor.calls
        let second = await service.matchTrip(tripId: tripId)
        let afterSecond = await reconstructor.calls

        XCTAssertEqual(first, 3)
        XCTAssertEqual(afterSecond, 3, "already-matched legs must not be re-requested")
        XCTAssertEqual(second.attempted, 0)
    }

    // MARK: - Harness

    private func report(
        legs: Int,
        behaviour: ScriptedReconstructor.Behaviour
    ) async throws -> RouteMatchReport {
        try await report(legs: legs, reconstructor: ScriptedReconstructor(behaviour))
    }

    private func report(
        legs: Int,
        reconstructor: ScriptedReconstructor,
        tripBudgetS: Double = 60,
        shouldContinue: @escaping () -> Bool = { true }
    ) async throws -> RouteMatchReport {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try seed(legs: legs, into: repository)
        let service = try makeService(
            repository: repository, reconstructor: reconstructor, tripBudgetS: tripBudgetS
        )
        return await service.matchTrip(tripId: tripId, shouldContinue: shouldContinue)
    }

    private func makeService(
        repository: TripRepository,
        reconstructor: ScriptedReconstructor,
        tripBudgetS: Double = 60
    ) throws -> RouteMatchService {
        let shipped = AppConfig.loadOrDie()
        // A non-empty base URL so the run is not reported as disabled; the
        // injected reconstructor is what actually answers, and nothing here
        // touches the network.
        let matching = TrackingConfig.Matching(
            baseURL: "https://routing.invalid", chunkSize: shipped.matching.chunkSize,
            confidenceMin: shipped.matching.confidenceMin, radiusM: shipped.matching.radiusM,
            timeoutS: shipped.matching.timeoutS, tripBudgetS: tripBudgetS,
            displayEpsilonM: shipped.matching.displayEpsilonM,
            routeMaxDetourRatio: shipped.matching.routeMaxDetourRatio,
            routeWaypointMinSpacingM: shipped.matching.routeWaypointMinSpacingM,
            routeWaypointRadiusM: shipped.matching.routeWaypointRadiusM
        )
        return RouteMatchService(
            repository: repository, matching: matching,
            provider: UnusedMatcher(), reconstructor: reconstructor
        )
    }

    /// A trip of `legs` EXIF drive segments — the imported shape, which is what
    /// goes to the reconstructor rather than the map matcher.
    private func seed(legs: Int, into repository: TripRepository) throws -> String {
        let segments = (0..<legs).map { index -> TripRepository.NewSegment in
            let base = Double(index)
            return TripRepository.NewSegment(
                mode: TransportMode.drive.rawValue,
                startedAt: 1_752_600_000 + base * 3_600,
                endedAt: 1_752_600_000 + base * 3_600 + 1_800,
                points: [
                    TripRepository.NewTrackpoint(ts: 1_752_600_000 + base * 3_600, lat: 64.0 + base * 0.1, lon: -20.0),
                    TripRepository.NewTrackpoint(
                        ts: 1_752_600_000 + base * 3_600 + 1_800, lat: 64.05 + base * 0.1, lon: -20.05
                    )
                ],
                source: SegmentSource.exif.rawValue
            )
        }
        return try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: "Bounds", startedAt: 1_752_600_000, endedAt: 1_752_600_000 + Double(legs) * 3_600,
                source: TripSource.importedPhotos.rawValue,
                segments: segments, stopsWithPhotos: [], routeAttachedPhotos: []
            )
        )
    }
}

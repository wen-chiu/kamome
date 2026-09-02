@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **The privacy notice says a recorded path is not sent. This is what makes
/// that true rather than remembered.**
///
/// `privacy_recorded_body` tells the user: *"The path your phone recorded is not
/// sent anywhere … If a future version ever sends it, what would be sent is the
/// whole recorded path — not a start and an end — and this notice will say so."*
/// Nothing enforced the promise. The day Capture Beta wires a map matcher onto a
/// shipping path, `RouteMatchService.shouldReconstruct` flips to `true` for
/// `.gpsHifi`/`.gpsPassive`, recorded traces start leaving the device, and the
/// notice becomes a false statement **with every existing test still green**.
///
/// That is the same class of failure as the attribution that shipped invisible
/// for months: a claim only a human remembers is not a guarantee.
///
/// **Why it is `nil` today is technical, not a privacy decision.** Map matching
/// speaks OSRM's `/match`; the endpoint is Geoapify, which has no map-matching
/// endpoint at all, so no matcher can be constructed — `RouteMatchService`
/// says so itself where `shouldReconstruct` refuses the leg. **The product
/// question is still open and deferred to Capture Beta** (ADR 2026-08-20 (d)'s
/// addendum records Chiu's lean and explicitly decides nothing). So this test
/// does not claim recorded traces must never be sent. It claims something
/// narrower and enforceable: **they are not sent today, and the day that
/// changes, the notice changes with it.**
///
/// → `Docs/release-readiness.md` S3b.
final class RouteMatchRecordedLegTests: XCTestCase {
    /// Stands in for whatever Capture Beta wires up. It never has to answer:
    /// the property under test is whether the leg is *offered*, which
    /// `matchTrip` reports as `attempted` before any request is made.
    private struct StubMatcher: RouteMatchProviding {
        func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? { nil }
    }

    /// The load-bearing one. Built exactly as the app builds it — no `provider:`
    /// — because a service constructed some other way proves nothing about what
    /// ships.
    func testTheShippedServiceNeverOffersARecordedLegToRouting() async throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try seedRecordedTrip(legs: 3, into: repository)

        let service = RouteMatchService(repository: repository, matching: shippedMatching())
        let report = await service.matchTrip(tripId: tripId)

        XCTAssertEqual(
            report.attempted, 0,
            """
            A recorded leg was offered to routing. If that is deliberate, the recorded trace now \
            leaves the device and `privacy_recorded_body` in App/Resources/Localizable.xcstrings \
            is FALSE in both languages — it promises the notice will say so first. Update the \
            notice (Chiu's wording, Docs/release-readiness.md S3) before this test is changed.
            """
        )
    }

    /// The control that stops the assertion above passing for the wrong reason.
    /// If routing were broken outright, `attempted` would be 0 for everything and
    /// the recorded assertion would read as a guarantee it is not making.
    func testTheSameShippedServiceStillOffersAnImportedLeg() async throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try seedImportedTrip(legs: 3, into: repository)

        let service = RouteMatchService(repository: repository, matching: shippedMatching())
        let report = await service.matchTrip(tripId: tripId)

        XCTAssertEqual(
            report.attempted, 3,
            "imported legs are the payload the notice DOES declare; if this is 0 the test above is vacuous"
        )
    }

    /// The positive control: the same recorded trip, through a service that has
    /// a matcher. It proves the first test can fail — that it is reading
    /// `shouldReconstruct` and not simply agreeing with a fixture.
    ///
    /// **Injecting the matcher here is the point, not a shortcut.** This is the
    /// shape Capture Beta will take, and it is what the first test must catch.
    func testAWiredMatcherIsExactlyWhatTheFirstTestCatches() async throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try seedRecordedTrip(legs: 3, into: repository)

        let service = RouteMatchService(
            repository: repository, matching: shippedMatching(), provider: StubMatcher()
        )
        let report = await service.matchTrip(tripId: tripId)

        XCTAssertEqual(
            report.attempted, 3,
            "with a matcher wired, recorded legs ARE offered — so the shipped-path assertion is not vacuous"
        )
    }

    // MARK: - Fixtures

    /// The app's own `matching` block, read from the shipped config. Nothing is
    /// substituted: `base_url` is `""` in the repository, and `attempted` is
    /// counted before that is consulted, so a disabled endpoint does not hide
    /// the property under test.
    private func shippedMatching() -> TrackingConfig.Matching {
        AppConfig.loadOrDie().matching
    }

    private func seedRecordedTrip(legs: Int, into repository: TripRepository) throws -> String {
        try seed(legs: legs, source: .gpsHifi, trip: .recorded, into: repository)
    }

    private func seedImportedTrip(legs: Int, into repository: TripRepository) throws -> String {
        try seed(legs: legs, source: .exif, trip: .importedPhotos, into: repository)
    }

    /// Drive legs, two points each, no `matchedPolyline` — the shape
    /// `shouldReconstruct` accepts on every axis **except** the one under test,
    /// so a `false` can only be the segment source.
    private func seed(
        legs: Int, source: SegmentSource, trip: TripSource, into repository: TripRepository
    ) throws -> String {
        let segments = (0..<legs).map { index -> TripRepository.NewSegment in
            let base = Double(index)
            let start = 1_752_600_000 + base * 3_600
            return TripRepository.NewSegment(
                mode: TransportMode.drive.rawValue,
                startedAt: start,
                endedAt: start + 1_800,
                points: [
                    TripRepository.NewTrackpoint(ts: start, lat: 64.0 + base * 0.1, lon: -20.0),
                    TripRepository.NewTrackpoint(ts: start + 1_800, lat: 64.05 + base * 0.1, lon: -20.05)
                ],
                source: source.rawValue
            )
        }
        return try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: "Recorded-leg fixture",
                startedAt: 1_752_600_000,
                endedAt: 1_752_600_000 + Double(legs) * 3_600,
                source: trip.rawValue,
                segments: segments, stopsWithPhotos: [], routeAttachedPhotos: []
            )
        )
    }
}

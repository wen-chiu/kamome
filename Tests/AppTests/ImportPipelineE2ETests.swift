@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
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
        XCTAssertEqual(detail.stops.count, 2)

        // One segment per inter-stop leg (typed-leg pass 2026-07-26), so each
        // stretch can carry its own reconstruction verdict — here the single
        // A→B leg, with the lone photo riding along inside it.
        XCTAssertEqual(detail.segments.count, 1, "two stops = one travel leg between them")
        XCTAssertEqual(detail.segments[0].segment.segmentSource, .exif)
        XCTAssertEqual(detail.segments[0].points.count, 3, "stop anchor, lone photo, stop anchor")

        // The whole point: an imported trip is first-class — RecapComposer maps
        // it into recap inputs with no special-casing.
        let legs = RecapComposer.legs(
            from: detail.segments,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        XCTAssertGreaterThanOrEqual(legs.flatMap(\.coordinates).count, 2)
        // No OSRM server in CI (`matching.base_url` ships ""), so the leg could
        // not be reconstructed — it must say so rather than pass as road (PD-2).
        XCTAssertEqual(legs.map(\.provenance), [.inferred])
        let recap = RecapComposer.trip(
            trip: detail.trip,
            legs: legs,
            stops: detail.stops,
            stats: nil,
            photosByStop: [:]
        )
        XCTAssertNotNil(recap, "imported trip must produce recap data unchanged")
        XCTAssertNil(recap?.shareURL, "the MVP film carries no unresolved QR (PD-4)")
        XCTAssertEqual(recap?.stops.count, 2)
    }

    /// PD-8: a walking-pace leg is classified `walk` and therefore never sent
    /// through the car profile — snapping a stroll to the nearest street would
    /// invent a drive that never happened.
    func testWalkPaceLegsAreClassifiedWalkAndStayUnrouted() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)

        // Stop A → a 70-minute, ~5 km amble → Stop B (the clusters must clear
        // the shipped 4 km stop radius to be two places) → a highway leg to C.
        let photos = [
            photo("a1", 0, 64.1466, -21.9426),
            photo("a2", 120, 64.1467, -21.9427),
            photo("b1", 4_200, 64.1916, -21.9420),
            photo("b2", 4_320, 64.1917, -21.9421),
            photo("c1", 7_000, 64.5000, -21.0000),
            photo("c2", 7_120, 64.5001, -21.0001)
        ]
        let tripId = try await service.importTrip(title: "Reykjavík", photos: photos)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))

        XCTAssertEqual(detail.segments.count, 2, "A→B and B→C")
        XCTAssertEqual(detail.segments.map(\.segment.mode), ["walk", "drive"],
                       "pace decides the mode, not a blanket road-trip assumption")
    }

    /// **An overnight gap is not slow travel** (Chiu 2026-08-02). Pace is only a
    /// signal while the elapsed time was plausibly spent moving; across a night
    /// it was not, and treating it as pace typed every inter-day leg of a
    /// multi-day trip as a walk — which is never routed, so it drew as a straight
    /// line through whatever lay between. On the real 11-day New Zealand trip
    /// that was 7 of 9 legs, crossing a lake and an alpine range.
    func testOvernightGapsAreDrivenNotWalked() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)

        // 60 km apart, photographed 13 hours apart: 4.6 km/h — walking pace by
        // the numbers, and impossible as an actual walk.
        let night = config.photoImport.paceUnknowableGapS + 3_600
        let photos = [
            photo("a1", 0, 64.1466, -21.9426),
            photo("a2", 120, 64.1467, -21.9427),
            photo("b1", night, 64.6800, -21.9420),
            photo("b2", night + 120, 64.6801, -21.9421)
        ]
        let tripId = try await service.importTrip(title: "Two days", photos: photos)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))

        XCTAssertEqual(detail.segments.map(\.segment.mode), ["drive"],
                       "a gap this long carries no pace signal — fall back to the road-trip assumption")
    }

    /// The dispatch (typed-leg pass): EXIF legs go to `/route` with vias, never
    /// to `/match`, whose Hidden-Markov model expects a dense trace.
    func testExifLegsAreDispatchedToTheRouteReconstructorNotTheMatcher() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let matcher = SpyMatcher()
        let reconstructor = SpyReconstructor(
            outcome: RouteMatchOutcome(
                geometry: [GeoPoint(lat: 64.264, lon: -20.516), GeoPoint(lat: 63.404, lon: -19.041)],
                confidence: 1
            )
        )
        let service = ImportService(repository: repository, config: config)
        // Routing is its own step since 2026-08-15 — `importTrip` returns as
        // soon as the trip is saved. A test that wants a routed trip now says
        // so, which is the dependency it always had and never stated.
        let routing = RouteMatchService(
            repository: repository, matching: config.matching,
            provider: matcher, reconstructor: reconstructor
        )

        let tripId = try await service.importTrip(
            title: "Iceland",
            photos: [
                photo("a1", 0, 64.264, -20.516),
                photo("a2", 120, 64.265, -20.515),
                photo("b1", 7_200, 63.404, -19.041),
                photo("b2", 7_320, 63.405, -19.040)
            ]
        )
        await routing.matchTrip(tripId: tripId)

        let matchCalls = await matcher.calls
        let routeCalls = await reconstructor.calls
        XCTAssertEqual(matchCalls, 0, "sparse EXIF legs must not go to /match")
        XCTAssertEqual(routeCalls, 1)

        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertNotNil(detail.segments[0].segment.matchedPolyline,
                        "a reconstructed leg stores its road geometry — that is what marks it reconstructed")
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

/// Counts calls so the dispatch can be asserted without a server. Actors
/// because both boundaries are `Sendable` and crossed from a detached context.
private actor SpyMatcher: RouteMatchProviding {
    private(set) var calls = 0

    func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? {
        calls += 1
        return nil
    }
}

private actor SpyReconstructor: RouteReconstructing {
    private(set) var calls = 0
    private let outcome: RouteMatchOutcome?

    init(outcome: RouteMatchOutcome?) {
        self.outcome = outcome
    }

    func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteMatchOutcome? {
        calls += 1
        return outcome
    }
}

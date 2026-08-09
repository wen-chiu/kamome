@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **The naming path itself** — geocoder → `StopNamer` → database.
///
/// This is the gap that let the 2026-08-03 throttle fix ship "green" while the
/// symptom survived in real films: the only coverage was `GeocodePolicy`, a pure
/// struct with no queue, no retry and no DB, and `StopNamer` owned a concrete
/// `CLGeocoder` so nothing else could reach it. These tests drive the real
/// `StopNamer` — real queue, real throttle, real `setStopName` writes — over a
/// stub geocoder, plus an env-gated run against the actual CLGeocoder.
final class StopNamerTests: XCTestCase {

    /// Records every lookup and answers however the test tells it to. Answers on
    /// the main queue, like CLGeocoder.
    private final class StubGeocoder: StopGeocoding {
        /// name for a coordinate, or nil to fail that lookup.
        var answer: (Double, Double) -> String?
        private(set) var lookupTimes: [TimeInterval] = []
        private(set) var lookups = 0

        init(answer: @escaping (Double, Double) -> String?) { self.answer = answer }

        func reverseGeocode(
            lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void
        ) {
            lookups += 1
            lookupTimes.append(Date.now.timeIntervalSince1970)
            let name = answer(lat, lon)
            DispatchQueue.main.async {
                completion(name, name == nil ? NSError(domain: "stub", code: 2) : nil)
            }
        }
    }

    /// A trip whose stops are all unnamed, straight out of the real importer.
    private func importedTrip(
        stops wanted: Int, config: TrackingConfig
    ) async throws -> (TripRepository, [StopRecord]) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)
        // Two photos per cluster, each cluster far enough apart in space and time
        // to survive `stop_radius_m` / `stop_split_gap_s`.
        var photos: [ImportPhoto] = []
        for index in 0..<wanted {
            let time = Double(index) * (config.photoImport.stopSplitGapS + 600)
            let lat = 64.0 + Double(index) * 0.5
            photos.append(ImportPhoto(assetId: "s\(index)-a", timestamp: time, lat: lat, lon: -20.0))
            photos.append(ImportPhoto(assetId: "s\(index)-b", timestamp: time + 60, lat: lat, lon: -20.0))
        }
        let tripId = try await service.importTrip(title: "naming", photos: photos)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops.count, wanted)
        XCTAssertTrue(detail.stops.allSatisfy { $0.name == nil }, "importer never names stops")
        return (repository, detail.stops)
    }

    /// A short throttle keeps the test quick without removing the throttle —
    /// spacing is the property under test, so it must still be enforced.
    private func geocode(minIntervalS: Double) -> TrackingConfig.Geocode {
        TrackingConfig.Geocode(minIntervalS: minIntervalS, cachePrecisionDeg: 0.001)
    }

    // MARK: - The path that was never covered

    func testEveryStopIsNamedAndPersisted() async throws {
        let config = AppConfig.loadOrDie()
        let geocode = self.geocode(minIntervalS: 0.05)
        let (repository, stops) = try await importedTrip(stops: 6, config: config)
        let stub = StubGeocoder { lat, _ in String(format: "Place %.1f", lat) }
        let namer = StopNamer(config: geocode, repository: repository, geocoder: stub)

        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(stops) { progress in
            if progress.isFinished { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 10)

        let named = try XCTUnwrap(try repository.detail(tripId: stops[0].tripId)).stops
        XCTAssertEqual(named.compactMap(\.name).count, 6, "every stop reaches the database named")
        XCTAssertEqual(namer.progress.named, 6)
    }

    /// **The 2026-08-03 regression, at the level it actually manifested.**
    ///
    /// One failed lookup must not release the throttle for the rest of the queue.
    /// Asserted on the *observed spacing between lookups*, which is what
    /// CLGeocoder's per-app rate limiter sees — `GeocodePolicy` alone could only
    /// ever prove that a variable was assigned.
    func testAFailedLookupStillCostsTheThrottle() async throws {
        let interval = 0.2
        let config = AppConfig.loadOrDie()
        let geocode = self.geocode(minIntervalS: interval)
        let (repository, stops) = try await importedTrip(stops: 5, config: config)
        // The second lookup fails; without charging the throttle, every later
        // stop fires immediately behind it.
        var seen = 0
        let stub = StubGeocoder { lat, _ in
            seen += 1
            return seen == 2 ? nil : String(format: "Place %.1f", lat)
        }
        let namer = StopNamer(config: geocode, repository: repository, geocoder: stub)

        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(stops) { progress in
            if progress.isFinished { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 20)

        XCTAssertEqual(stub.lookups, 5)
        let gaps = zip(stub.lookupTimes, stub.lookupTimes.dropFirst()).map { $1 - $0 }
        for (index, gap) in gaps.enumerated() {
            XCTAssertGreaterThanOrEqual(
                gap, interval * 0.8,
                "lookup \(index + 2) came \(gap)s after the last one — the throttle was released by a failure"
            )
        }
        // The failed stop stays unnamed and the rest are unaffected: "some named,
        // some not" is correct here, unlike the burst failure it used to cause.
        let named = try XCTUnwrap(try repository.detail(tripId: stops[0].tripId)).stops
        XCTAssertEqual(named.compactMap(\.name).count, 4)
        XCTAssertEqual(namer.progress.completed, 5, "a failed stop is finished, not pending")
        XCTAssertTrue(namer.progress.isFinished)
    }

    /// The export gate's contract: progress is not finished until every stop has
    /// left the queue, so `TripDetailModel.isNamingStops` cannot go false early.
    func testProgressStaysUnfinishedUntilTheLastStop() async throws {
        let config = AppConfig.loadOrDie()
        let geocode = self.geocode(minIntervalS: 0.1)
        let (repository, stops) = try await importedTrip(stops: 4, config: config)
        let stub = StubGeocoder { lat, _ in String(format: "Place %.1f", lat) }
        let namer = StopNamer(config: geocode, repository: repository, geocoder: stub)

        var snapshots: [StopNamer.Progress] = []
        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(stops) { progress in
            snapshots.append(progress)
            if progress.isFinished { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 10)

        XCTAssertEqual(snapshots.first?.total, 4)
        XCTAssertEqual(snapshots.first?.completed, 0)
        XCTAssertFalse(snapshots.first?.isFinished ?? true, "the gate must be closed at the start")
        XCTAssertTrue(snapshots.dropLast().allSatisfy { !$0.isFinished }, "finished exactly once, at the end")
    }

    // MARK: - The real thing

    /// **CLGeocoder → StopNamer → DB, for real.** Env-gated because it needs a
    /// network and hits Apple's service; run it on the device or simulator when
    /// verifying the naming path end to end:
    ///
    ///     TEST_RUNNER_KAMOME_LIVE_GEOCODE=1 xcodebuild -scheme Kamome test \
    ///       -only-testing:KamomeTests/StopNamerTests/testLiveGeocoderNamesStops …
    ///
    /// Coordinates are the committed synthetic fixture's, never a real trip dump
    /// (CLAUDE.md §0).
    func testLiveGeocoderNamesStops() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_LIVE_GEOCODE"] == "1",
            "Live network test — set KAMOME_LIVE_GEOCODE=1."
        )
        let config = AppConfig.loadOrDie()
        let (repository, stops) = try await importedTrip(stops: 3, config: config)
        let namer = StopNamer(config: config.geocode, repository: repository, geocoder: CLGeocoderStopGeocoder())

        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(stops) { progress in
            if progress.isFinished { done.fulfill() }
        }
        // 3 stops at the shipped 2 s throttle, plus network.
        await fulfillment(of: [done], timeout: 60)

        let named = try XCTUnwrap(try repository.detail(tripId: stops[0].tripId)).stops
        print("KAMOME_LIVE_GEOCODE named \(namer.progress.named)/\(namer.progress.total)")
        XCTAssertEqual(
            named.compactMap(\.name).count, 3,
            "every stop should come back named — if this fails, read the KamomeLog geocode errors"
        )
        XCTAssertTrue(named.compactMap(\.name).allSatisfy { !$0.isEmpty })
    }
}

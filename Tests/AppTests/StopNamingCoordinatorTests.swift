@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **Naming belongs to the app, not to the screen that asked for it** (#159,
/// ADR 2026-10-01). `StopNamer` was owned by `TripDetailModel`, so leaving Trip
/// Detail dropped the queue and coming back started the wait again. These
/// drive the real coordinator and the real `StopNamer` over a stub geocoder.
@MainActor
final class StopNamingCoordinatorTests: XCTestCase {
    /// Names every coordinate after a short wait, on the main queue like
    /// CLGeocoder, and counts what it was asked.
    private final class StubGeocoder: StopGeocoding {
        private(set) var lookups = 0

        func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
            lookups += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                completion(String(format: "Place %.1f", lat), nil)
            }
        }
    }

    /// Stands in for a screen: it is what `onChange` holds weakly.
    private final class Screen {
        var heard: [StopNamer.Progress] = []
    }

    private let geocode = TrackingConfig.Geocode(minIntervalS: 0.05, cachePrecisionDeg: 0.001)

    private func importedTrip(stops wanted: Int) async throws -> (TripRepository, String) {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        var photos: [ImportPhoto] = []
        for index in 0..<wanted {
            let time = Double(index) * (config.photoImport.stopSplitGapS + 600)
            let lat = 64.0 + Double(index) * 0.5
            photos.append(ImportPhoto(assetId: "s\(index)-a", timestamp: time, lat: lat, lon: -20.0))
            photos.append(ImportPhoto(assetId: "s\(index)-b", timestamp: time + 60, lat: lat, lon: -20.0))
        }
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: "naming", photos: photos)
        return (repository, tripId)
    }

    private func stops(_ repository: TripRepository, _ tripId: String) throws -> [StopRecord] {
        try XCTUnwrap(try repository.detail(tripId: tripId)).stops
    }

    /// Waits on the condition rather than on the clock (#143). Reaching the
    /// ceiling returns quietly; the assertions after it say what was missing.
    private func settle(until done: () throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while try !done(), Date.now < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func start(
        _ coordinator: StopNamingCoordinator, _ repository: TripRepository, _ tripId: String, for screen: Screen
    ) throws {
        coordinator.start(
            tripId: tripId, stops: try stops(repository, tripId), repository: repository, config: geocode, for: screen
        ) { [weak screen] progress in
            screen?.heard.append(progress)
        }
    }

    /// The defect itself: the screen goes on stop one, and every stop is still
    /// named.
    func testNamingFinishesAfterTheScreenThatStartedItIsGone() async throws {
        let (repository, tripId) = try await importedTrip(stops: 5)
        let stub = StubGeocoder()
        let coordinator = StopNamingCoordinator { stub }
        var screen: Screen? = Screen()
        try start(coordinator, repository, tripId, for: try XCTUnwrap(screen))
        XCTAssertTrue(coordinator.isNaming(tripId))
        screen = nil

        try await settle { try self.stops(repository, tripId).allSatisfy { $0.name != nil } && !coordinator.isNaming(tripId) }
        XCTAssertEqual(try stops(repository, tripId).compactMap(\.name).count, 5)
        XCTAssertEqual(stub.lookups, 5)
        XCTAssertNil(coordinator.progress[tripId], "a finished run is let go")
    }

    /// A screen that opens mid-run joins it: no stop is asked twice, and it
    /// hears where the run has got to rather than a count from zero.
    func testAScreenOpenedMidRunJoinsItInsteadOfStartingAnother() async throws {
        let (repository, tripId) = try await importedTrip(stops: 6)
        let stub = StubGeocoder()
        let coordinator = StopNamingCoordinator { stub }
        let first = Screen()
        try start(coordinator, repository, tripId, for: first)
        try await settle { (first.heard.last?.completed ?? 0) >= 2 }

        let second = Screen()
        try start(coordinator, repository, tripId, for: second)
        let joinedAt = try XCTUnwrap(second.heard.first)
        XCTAssertEqual(joinedAt.total, 6, "the stops were queued a second time")
        XCTAssertGreaterThanOrEqual(joinedAt.completed, 2)

        try await settle { !coordinator.isNaming(tripId) && second.heard.last?.isFinished == true }
        XCTAssertEqual(stub.lookups, 6, "one request per stop, however many screens ask")
        XCTAssertEqual(first.heard.last?.isFinished, true)
        XCTAssertEqual(second.heard.last, StopNamer.Progress(total: 6, completed: 6, named: 6))
        XCTAssertEqual(try stops(repository, tripId).compactMap(\.name).count, 6)
    }

    /// One screen asking again (it reappears) is still one listener and one run.
    func testTheSameScreenAskingAgainIsHeardOnce() async throws {
        let (repository, tripId) = try await importedTrip(stops: 3)
        let stub = StubGeocoder()
        let coordinator = StopNamingCoordinator { stub }
        let screen = Screen()
        try start(coordinator, repository, tripId, for: screen)
        try start(coordinator, repository, tripId, for: screen)
        try await settle { !coordinator.isNaming(tripId) && screen.heard.last?.isFinished == true }
        XCTAssertEqual(stub.lookups, 3)
        XCTAssertEqual(screen.heard.filter(\.isFinished).count, 1, "the last stop was reported twice")
    }

    /// A deleted trip's stops stop being sent (`TripDeletion`).
    func testCancellingStopsBeforeTheNextStop() async throws {
        let (repository, tripId) = try await importedTrip(stops: 6)
        let stub = StubGeocoder()
        let coordinator = StopNamingCoordinator { stub }
        let screen = Screen()
        try start(coordinator, repository, tripId, for: screen)
        try await settle { stub.lookups >= 1 }
        coordinator.cancel(tripId: tripId)
        let askedAtCancel = stub.lookups

        try await settle { coordinator.progress[tripId] == nil }
        try await Task.sleep(nanoseconds: 300_000_000) // several throttle intervals
        XCTAssertEqual(stub.lookups, askedAtCancel, "a lookup was sent after the cancel")
        XCTAssertNil(coordinator.progress[tripId])
    }

    /// Nothing to name: no run is kept, and nobody is told naming began.
    func testATripWithEveryStopNamedStartsNothing() async throws {
        let (repository, tripId) = try await importedTrip(stops: 2)
        for stop in try stops(repository, tripId) {
            try repository.setStopName(stopId: stop.id, name: "Named")
            try repository.setStopLocality(stopId: stop.id, locality: "Town")
            try repository.setStopTimeZone(stopId: stop.id, timeZone: "Atlantic/Reykjavik")
        }
        let stub = StubGeocoder()
        let coordinator = StopNamingCoordinator { stub }
        let screen = Screen()
        try start(coordinator, repository, tripId, for: screen)
        XCTAssertFalse(coordinator.isNaming(tripId))
        XCTAssertTrue(screen.heard.isEmpty)
        XCTAssertEqual(stub.lookups, 0)
    }

    /// A caller's copy of the trip can be one read behind. Handing back a stop
    /// that was just named must not ask about it again.
    func testAStaleCopyOfANamedStopIsNotAskedAgain() async throws {
        let (repository, tripId) = try await importedTrip(stops: 3)
        let stale = try stops(repository, tripId)
        let stub = StubGeocoder()
        let namer = StopNamer(config: geocode, repository: repository, geocoder: stub)
        // Asking again reports the progress again, so the expectation is
        // fulfilled on the first finish only.
        let done = expectation(description: "naming finished")
        var finishes = 0
        namer.nameUnnamedStops(stale) { progress in
            guard progress.isFinished else { return }
            finishes += 1
            if finishes == 1 { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 10)

        namer.nameUnnamedStops(stale)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(stub.lookups, 3)
        XCTAssertEqual(namer.progress, StopNamer.Progress(total: 3, completed: 3, named: 3))
    }
}

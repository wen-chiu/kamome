@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **One throttle for every lookup the app sends Apple** (#159, ADR 2026-10-01).
///
/// `StopNamer`, Discovery's card naming and `TripJourneyNaming` each throttled
/// only themselves, so together they could send about twice what
/// `geocode.min_interval_s` allows. These drive the real gate over a stub in
/// place of the Apple call, and assert on what Apple's limiter would see: when
/// each request started, and in which order.
@MainActor
final class GeocodeGateTests: XCTestCase {
    /// Stands in for the Apple call: records each request and answers after a
    /// short wait, like a network round trip.
    private final class Apple {
        private(set) var asked: [Double] = []
        private(set) var started: [ContinuousClock.Instant] = []
        private(set) var finished: [ContinuousClock.Instant] = []
        private(set) var inFlight = 0
        private(set) var peakInFlight = 0

        @MainActor
        func place(lat: Double, lon: Double) async -> GeocodeGate.Answer {
            asked.append(lat)
            started.append(.now)
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
            try? await Task.sleep(for: .milliseconds(20))
            inFlight -= 1
            finished.append(.now)
            return GeocodeGate.Answer(
                place: GeocodedPlace(name: "Place \(lat)", locality: "Town", country: "Country", countryCode: "IS"),
                error: nil
            )
        }
    }

    private func gate(over apple: Apple) -> GeocodeGate {
        GeocodeGate { lat, lon in await apple.place(lat: lat, lon: lon) }
    }

    /// Lets the tasks above reach the gate, which they do in the order made.
    private func settle(until done: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !done(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// The property #159 is about: whoever asks, a request starts no sooner
    /// than the interval after the last one finished, and never beside it.
    func testEveryCallerSharesOneThrottle() async throws {
        let interval = 0.15
        let apple = Apple()
        let gate = gate(over: apple)
        let asks: [(Double, GeocodeGate.Priority)] = [
            (1, .stop), (2, .card), (3, .tripFlag), (4, .stop), (5, .card)
        ]
        await withTaskGroup(of: Void.self) { group in
            for (lat, priority) in asks {
                group.addTask {
                    _ = await gate.place(lat: lat, lon: 0, priority: priority, minIntervalS: interval)
                }
            }
        }
        XCTAssertEqual(apple.asked.count, 5)
        XCTAssertEqual(apple.peakInFlight, 1, "two lookups were out at once")
        for index in 1..<apple.started.count {
            let gap = seconds(apple.started[index] - apple.finished[index - 1])
            XCTAssertGreaterThanOrEqual(
                gap, interval * 0.8, "lookup \(index + 1) started \(gap)s after the last one finished"
            )
        }
    }

    /// Stop names hold the film button; a card's title holds nothing. A stop
    /// that asks while cards are waiting goes ahead of them.
    func testAStopGoesAheadOfCardsThatAskedFirst() async throws {
        let apple = Apple()
        let gate = gate(over: apple)
        var tasks: [Task<Void, Never>] = []
        func ask(_ lat: Double, _ priority: GeocodeGate.Priority) async throws {
            let before = gate.requestCount
            tasks.append(Task { _ = await gate.place(lat: lat, lon: 0, priority: priority, minIntervalS: 0.1) })
            try await settle { gate.requestCount > before }
        }
        try await ask(1, .card)      // nothing waiting: goes at once
        try await ask(2, .card)
        try await ask(3, .card)
        try await ask(4, .tripFlag)
        try await ask(5, .stop)
        for task in tasks { await task.value }
        XCTAssertEqual(apple.asked, [1, 5, 4, 2, 3])
    }

    /// `TripJourneyNaming` and `StopNamer` ask about a new trip's first stop at
    /// the same moment. One request answers both.
    func testTheSameCoordinateAskedTogetherIsOneRequest() async throws {
        let apple = Apple()
        let gate = gate(over: apple)
        async let flag = gate.place(lat: 7, lon: 8, priority: .tripFlag, minIntervalS: 0.05)
        async let stop = gate.place(lat: 7, lon: 8, priority: .stop, minIntervalS: 0.05)
        let answers = await [flag, stop]
        XCTAssertEqual(apple.asked.count, 1)
        XCTAssertEqual(answers.map(\.place?.name), ["Place 7.0", "Place 7.0"])
    }

    /// The whole path the app ships: the real `StopNamer` and the real place
    /// geocoder, both through one gate. Cards already waiting let the stops by,
    /// every stop is named, and the spacing holds across the two callers.
    func testStopNamerGoesAheadOfDiscoveryCardsAndBothKeepTheSpacing() async throws {
        let interval = 0.1
        let apple = Apple()
        let gate = gate(over: apple)
        let (repository, stops) = try await importedTrip(stops: 3)

        let cards = CLPlaceGeocoder(priority: .card, minIntervalS: interval, gate: gate)
        var cardTasks: [Task<PlaceName?, Never>] = []
        for card in 0..<3 {
            let before = gate.requestCount
            cardTasks.append(Task { await cards.place(lat: Double(card), lon: 100) })
            try await settle { gate.requestCount > before }
        }

        let namer = StopNamer(
            config: TrackingConfig.Geocode(minIntervalS: interval, cachePrecisionDeg: 0.001),
            repository: repository,
            geocoder: CLGeocoderStopGeocoder(minIntervalS: interval, gate: gate)
        )
        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(stops) { if $0.isFinished { done.fulfill() } }
        await fulfillment(of: [done], timeout: 10)
        for task in cardTasks { _ = await task.value }

        // Card 0 was already out; then the three stops; then the cards left.
        XCTAssertEqual(apple.asked, [0] + stops.map(\.lat) + [1, 2])
        let named = try XCTUnwrap(try repository.detail(tripId: stops[0].tripId)).stops
        XCTAssertEqual(named.compactMap(\.name).count, 3)
        XCTAssertTrue(named.allSatisfy { $0.locality == "Town" })
        XCTAssertEqual(apple.peakInFlight, 1)
        for index in 1..<apple.started.count {
            let gap = seconds(apple.started[index] - apple.finished[index - 1])
            XCTAssertGreaterThanOrEqual(gap, interval * 0.8, "lookup \(index + 1) came \(gap)s after the last")
        }
    }

    /// Unnamed stops straight out of the real importer, far enough apart to be
    /// separate stops and separate cache cells.
    private func importedTrip(stops wanted: Int) async throws -> (TripRepository, [StopRecord]) {
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
            .importTrip(title: "gate", photos: photos)
        return (repository, try XCTUnwrap(try repository.detail(tripId: tripId)).stops)
    }
}

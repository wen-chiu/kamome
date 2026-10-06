@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **The discovery home, driven over stubs** (2026-09-17): a library in, cards
/// out, a trip only when a card is opened, and the same trip on the next scan.
@MainActor
final class JourneyDiscoveryModelTests: XCTestCase {
    typealias StubLibrary = DiscoveryStubLibrary
    typealias StubGeocoder = DiscoveryStubGeocoder

    let week = 7.0 * 86_400
    /// A fixed "now" far enough past the photographs that they are inside the
    /// lookback window.
    let now = Date(timeIntervalSince1970: 60 * 7 * 86_400)

    func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// A photograph at home every week, the evening before each week mark where
    /// the trips below depart. Never *at* the mark: a photograph at home ends a
    /// journey (R1, 2026-09-25), and one sharing a trip's first second would be
    /// ordered by asset id — the alphabet, not the fixture, would decide.
    func homeYear() -> [ImportPhoto] {
        (0..<52).map { photo("home-\($0)", Double($0) * week - 3 * 3_600, 25.04, 121.56) }
    }

    func library() -> [ImportPhoto] {
        var photos = homeYear()
        // Japan: Tokyo then Kyoto, twelve and six photographs.
        photos += (0..<12).map { photo("jp-\($0)", 10 * week + Double($0) * 1_800, 35.68, 139.65) }
        photos += (0..<6).map { photo("kyoto-\($0)", 10 * week + 2 * 86_400 + Double($0) * 1_800, 35.01, 135.77) }
        // Whitehorse, nine photographs in one place.
        photos += (0..<9).map { photo("yt-\($0)", 30 * week + Double($0) * 1_800, 60.72, -135.05) }
        return photos
    }

    struct Harness {
        let model: JourneyDiscoveryModel
        let library: StubLibrary
        let geocoder: StubGeocoder
        let repository: TripRepository
        let defaults: UserDefaults
    }

    /// - Parameter defaults: an earlier harness's store, to stand for a relaunch.
    func makeHarness(defaults existing: UserDefaults? = nil) throws -> Harness {
        let defaults: UserDefaults
        if let existing {
            defaults = existing
        } else {
            let suite = "kamome.test.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        }
        let library = StubLibrary()
        library.photos = self.library()
        let geocoder = StubGeocoder()
        geocoder.table = [
            (25.04, PlaceName(country: "Taiwan", countryCode: "TW", region: "Taipei", locality: "Taipei")),
            (35.68, PlaceName(country: "Japan", countryCode: "JP", region: "Tokyo", locality: "Shibuya")),
            (60.72, PlaceName(country: "Canada", countryCode: "CA", region: "Yukon", locality: "Whitehorse"))
        ]
        // A zero throttle, so the naming task finishes inside a test.
        let fast = try Self.shippedConfig(geocodeInterval: 0)
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let model = JourneyDiscoveryModel(
            config: fast, repository: repository, source: library, photoAccess: library,
            geocoder: geocoder, defaults: defaults, homeCountryCode: "TW", now: { [now] in now }
        )
        return Harness(model: model, library: library, geocoder: geocoder, repository: repository, defaults: defaults)
    }

    /// `@escaping` because the hiding tests in another file call it: not
    /// private, the module-emit pass rejects a non-escaping `condition` here.
    func waitUntil(_ description: String, _ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), description)
    }

    // MARK: - Discovery

    /// The sample is Kamome's, not a journey anyone took (ADR 2026-09-28-sample-trip).
    func testTheSampleTripIsNeverAJourney() throws {
        let harness = try makeHarness()
        try SampleTrip.create(repository: harness.repository, vehicleId: "car-red")
        harness.model.loadTrips()
        XCTAssertTrue(harness.model.journeys.isEmpty, "the sample must not appear among the person's journeys")
    }

    func testAScanShowsJourneysByYearWithoutWritingATrip() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()

        XCTAssertEqual(harness.model.phase, .ready)
        XCTAssertEqual(harness.model.journeys.count, 2)
        XCTAssertEqual(harness.model.journeys.map(\.photoCount), [9, 18], "newest first")
        XCTAssertEqual(harness.model.journeys[1].stopCount, 2, "Tokyo and Kyoto")
        XCTAssertTrue(harness.model.journeys.allSatisfy { !$0.isImported })
        XCTAssertEqual(try harness.repository.allTrips().count, 0, "nothing is written by a scan")
        XCTAssertEqual(harness.model.sections.count, 1, "both journeys fall in one year of the fixed clock")

        // The scan asked for the lookback window, ending now.
        guard case let .dateRange(_, to) = try XCTUnwrap(harness.library.queries.first) else {
            return XCTFail("discovery scans a date range")
        }
        XCTAssertEqual(to, now)
    }

    func testJourneysAreNamedFromOneLookupEach() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        await waitUntil("both journeys named") { harness.model.journeys.allSatisfy { $0.name != nil } }

        XCTAssertEqual(harness.model.journeys[0].name, JourneyName(title: "Whitehorse", flag: "🇨🇦"))
        XCTAssertEqual(harness.model.journeys[1].name, JourneyName(title: "Japan", flag: "🇯🇵"))
        XCTAssertEqual(harness.geocoder.lookups, 2, "one per journey, and nothing else")

        // Names are cached: a fresh model over the same defaults asks nothing.
        let again = JourneyDiscoveryModel(
            config: AppConfig.loadOrDie(), repository: harness.repository, source: harness.library,
            photoAccess: harness.library, geocoder: harness.geocoder, defaults: harness.defaults,
            homeCountryCode: "TW", now: { [now] in now }
        )
        await again.refresh()
        XCTAssertEqual(again.journeys.map { $0.name?.title }, ["Whitehorse", "Japan"])
        XCTAssertEqual(harness.geocoder.lookups, 2)
    }

    /// **Where the user lives is never sent anywhere** (2026-09-18). The
    /// detector estimates home on device to decide what counts as "away", and
    /// the first version then sent that estimate to Apple's geocoder to learn
    /// home's country. Home is the most sensitive coordinate in the library;
    /// the naming rule only ever needed its country, and the device's region
    /// already knows it. This fails if a home lookup ever comes back.
    func testTheHomeLocationIsNeverSentToTheGeocoder() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        await waitUntil("named") { harness.model.journeys.allSatisfy { $0.name != nil } }

        // The invented home in `library()` sits at latitude 25.04.
        let homeLatitude = 25.04
        XCTAssertFalse(
            harness.geocoder.askedLatitudes.contains { abs($0 - homeLatitude) < 0.5 },
            "the geocoder was asked about the home location: \(harness.geocoder.askedLatitudes)"
        )
        XCTAssertFalse(harness.geocoder.askedLatitudes.isEmpty, "journeys are still named")
    }

    /// **Only a stop is ever sent** (Chiu's §0 scope, ADR 2026-09-16, PR #72:
    /// 「停留點一定只能送 apple 去問」). A journey whose photographs never cluster
    /// into a stop used to be looked up at the centroid of all of them — an
    /// average position that is not a stop. It is now not looked up at all, and
    /// keeps the month title it had.
    func testAJourneyWithNoStopIsNeverLookedUp() async throws {
        let harness = try makeHarness()
        let home = homeYear()
        // Eight photographs, each ~11 km from the last: every cluster holds one,
        // so none reaches `min_photos_per_stop` and the journey has no stop.
        let scattered = (0..<8).map {
            photo("far-\($0)", 40 * week + Double($0) * 1_800, 45.0 + Double($0) * 0.1, 7.0)
        }
        harness.library.photos = home + scattered
        await harness.model.refresh()

        let journey = try XCTUnwrap(harness.model.journeys.first)
        XCTAssertEqual(journey.stopCount, 0, "the fixture must produce a stopless journey")
        XCTAssertNil(journey.nameLookupLat, "no stop, so nothing to look up")
        // Give a naming task every chance to run, then prove it sent nothing.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(harness.geocoder.askedLatitudes.isEmpty, "sent: \(harness.geocoder.askedLatitudes)")
        XCTAssertNil(journey.name)
    }

    // MARK: - Opening

    func testOpeningAJourneyImportsItOnceAndFindsItAgain() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        await waitUntil("named") { harness.model.journeys.allSatisfy { $0.name != nil } }
        let japan = try XCTUnwrap(harness.model.journeys.last)

        let opened = await harness.model.open(japan)
        let tripId = try XCTUnwrap(opened)
        let trip = try XCTUnwrap(try harness.repository.detail(tripId: tripId)?.trip)
        // Restated 2026-10-01 (#165, Chiu's title rule): this used to pin the
        // card's name being copied into `trip.title`. The trip is now stored
        // unnamed and called by its place wherever it is shown, flag included.
        // Restated again 2026-10-02 (#168): unnamed is an empty title, not the
        // start date as a string.
        XCTAssertEqual(trip.title, TripTitle.unnamed, "stored unnamed, not under the card's name")
        XCTAssertEqual(
            TripTitle.film(trip, cache: JourneyNameCache(defaults: harness.defaults), homeCountryCode: "TW"),
            "🇯🇵 Japan", "the resolved name is what the trip is called"
        )
        XCTAssertEqual(trip.discoveryKey, japan.id)
        XCTAssertEqual(trip.tripSource, .importedPhotos, "honest provenance survives discovery")

        // The card is now the trip, under the same id, so it does not jump.
        let stored = try XCTUnwrap(harness.model.journeys.first { $0.id == japan.id })
        XCTAssertEqual(stored.tripId, tripId)
        XCTAssertEqual(stored.name?.title, "Japan")

        // A rescan finds the trip and does not import a second one.
        await harness.model.refresh()
        XCTAssertEqual(try harness.repository.allTrips().count, 1)
        XCTAssertEqual(harness.model.journeys.count, 2)
        let reopened = await harness.model.open(stored)
        XCTAssertEqual(reopened, tripId)
    }

    func testDeletingAStoredJourneyRemovesTheTrip() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let japan = try XCTUnwrap(harness.model.journeys.last)
        _ = await harness.model.open(japan)
        XCTAssertEqual(try harness.repository.allTrips().count, 1)

        let stored = try XCTUnwrap(harness.model.journeys.first { $0.id == japan.id })
        harness.model.delete(stored)
        XCTAssertEqual(try harness.repository.allTrips().count, 0)
        XCTAssertFalse(harness.model.journeys.contains { $0.id == japan.id })
    }

    // MARK: - Access

    func testWithoutAccessNothingIsScanned() async throws {
        let harness = try makeHarness()
        harness.library.access = .undetermined
        await harness.model.refresh()
        XCTAssertEqual(harness.model.access, .undetermined)
        XCTAssertEqual(harness.model.phase, .ready)
        XCTAssertTrue(harness.library.queries.isEmpty, "the welcome card asks; a passive appear does not")

        harness.library.access = .denied
        await harness.model.requestAccessAndDiscover()
        XCTAssertEqual(harness.model.access, .denied)
        XCTAssertTrue(harness.library.queries.isEmpty)
    }

    func testLimitedAccessScansAndOffersThePicker() async throws {
        let harness = try makeHarness()
        harness.library.access = .limited
        await harness.model.refresh()
        XCTAssertTrue(harness.model.isLimitedAccess)
        XCTAssertEqual(harness.model.journeys.count, 2, "the selected subset is still scanned")

        harness.model.selectMorePhotos()
        XCTAssertEqual(harness.library.pickerPresented, 1)
    }

    func testStoredTripsAppearBesideDiscoveredOnes() async throws {
        let harness = try makeHarness()
        // A trip imported the old way, with no discovery key.
        let service = ImportService(repository: harness.repository, config: AppConfig.loadOrDie())
        let manual = (0..<4).map { photo("m-\($0)", 45 * week + Double($0) * 3_600, 64.1 + Double($0) * 0.2, -21.9) }
        let tripId = try await service.importTrip(title: "Iceland by album", photos: manual)

        await harness.model.refresh()
        XCTAssertEqual(harness.model.journeys.count, 3)
        let stored = try XCTUnwrap(harness.model.summary(forTrip: tripId))
        XCTAssertEqual(stored.id, tripId, "no discovery key, so the trip id is the card's id")
        XCTAssertEqual(stored.headline, "Iceland by album")
        XCTAssertEqual(stored.provenance, .fromPhotos)
        XCTAssertEqual(stored.photoCount, 4)
    }

    /// **A coordinate is never a milestone** (Chiu, 2026-09-23). A stop stored
    /// before ADR 2026-09-23 can carry "20.943929, 116.686423" as its name; the
    /// timeline read it straight from the table and printed it as a place.
    func testAStopNamedByItsCoordinateIsNotAMilestone() async throws {
        let harness = try makeHarness()
        let service = ImportService(repository: harness.repository, config: AppConfig.loadOrDie())
        // Two places half a degree apart, three photographs each — two stops.
        let manual = (0..<6).map {
            photo("m-\($0)", 45 * week + Double($0) * 1_800, $0 < 3 ? 64.1 : 64.6, -21.9)
        }
        let tripId = try await service.importTrip(title: "Iceland by album", photos: manual)
        let stops = try XCTUnwrap(harness.repository.detail(tripId: tripId)).stops
        guard stops.count >= 2 else { return XCTFail("the fixture needs two stops to name, got \(stops.count)") }
        try harness.repository.setStopName(stopId: stops[0].id, name: "20.943929, 116.686423")
        try harness.repository.setStopName(stopId: stops[1].id, name: "Reykjavík")

        await harness.model.refresh()
        let stored = try XCTUnwrap(harness.model.summary(forTrip: tripId))
        XCTAssertEqual(stored.milestones, ["Reykjavík"])
        XCTAssertEqual(stored.stopCount, stops.count, "the stop still counts; only its name is withheld")
    }

    /// The visit line counts abroad only, once the country is known.
    func testAJourneyAbroadKnowsWhichVisitItWas() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        await waitUntil("both journeys named") { harness.model.journeys.allSatisfy { $0.countryCode != nil } }

        let japan = try XCTUnwrap(harness.model.journeys.first { $0.countryCode == "JP" })
        XCTAssertEqual(harness.model.visits[japan.id], JourneyChronicle.Visit(ordinal: 1, country: "Japan"))
    }

    /// `discovery.show_home_gaps` hides the "at home" rows and nothing else.
    func testHomeGapsFollowTheirFlag() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        XCTAssertEqual(harness.model.homeGaps.count, 1, "two journeys, one stretch at home between them")

        let hidden = JourneyDiscoveryModel(
            config: try Self.shippedConfig(geocodeInterval: 0, showHomeGaps: false),
            repository: harness.repository, source: harness.library, photoAccess: harness.library,
            geocoder: harness.geocoder, defaults: harness.defaults, homeCountryCode: "TW", now: { [now] in now }
        )
        await hidden.refresh()
        XCTAssertEqual(hidden.journeys.count, 2)
        XCTAssertTrue(hidden.homeGaps.isEmpty)
    }
}

extension JourneyDiscoveryModelTests {
    /// The shipped config with the geocode throttle replaced — test-only, so
    /// the naming task runs inside a test's patience.
    static func shippedConfig(geocodeInterval seconds: Double, showHomeGaps: Bool = true) throws -> TrackingConfig {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "TrackingConfig", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var geocode = try XCTUnwrap(json["geocode"] as? [String: Any])
        geocode["min_interval_s"] = seconds
        json["geocode"] = geocode
        var discovery = try XCTUnwrap(json["discovery"] as? [String: Any])
        discovery["show_home_gaps"] = showHomeGaps
        json["discovery"] = discovery
        return try TrackingConfigLoader.load(from: JSONSerialization.data(withJSONObject: json))
    }
}

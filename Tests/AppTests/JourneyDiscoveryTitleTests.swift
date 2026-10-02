@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **What a trip made in Journey Discovery is called, and what a failed tap
/// says** (#164, #165, #166; Chiu's title rule, 2026-10-01).
@MainActor
final class JourneyDiscoveryTitleTests: XCTestCase {
    private let week = 7.0 * 86_400
    private let now = Date(timeIntervalSince1970: 60 * 7 * 86_400)

    private struct Harness {
        let model: JourneyDiscoveryModel
        let library: DiscoveryStubLibrary
        let geocoder: DiscoveryStubGeocoder
        let repository: TripRepository
        let defaults: UserDefaults
        let database: AppDatabase
    }

    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// A photograph at home every week, the evening before each week mark
    /// (as in `JourneyDiscoveryModelTests`).
    private func homeYear() -> [ImportPhoto] {
        (0..<52).map { photo("home-\($0)", Double($0) * week - 3 * 3_600, 25.04, 121.56) }
    }

    /// One town, two places in it: far enough apart to be two stops, so the
    /// journey is a trip, and close enough to be named after the town.
    private func oneTownLibrary() -> [ImportPhoto] {
        var photos = homeYear()
        photos += (0..<6).map { photo("yt-a-\($0)", 30 * week + Double($0) * 1_800, 60.72, -135.05) }
        photos += (0..<5).map { photo("yt-b-\($0)", 30 * week + 86_400 + Double($0) * 1_800, 60.80, -135.20) }
        return photos
    }

    private func makeHarness(photos: [ImportPhoto]) throws -> Harness {
        let suite = "kamome.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let library = DiscoveryStubLibrary()
        library.photos = photos
        let geocoder = DiscoveryStubGeocoder()
        geocoder.table = [
            (35.68, PlaceName(country: "Japan", countryCode: "JP", region: "Tokyo", locality: "Shibuya")),
            (60.72, PlaceName(country: "Canada", countryCode: "CA", region: "Yukon", locality: "Whitehorse"))
        ]
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let model = JourneyDiscoveryModel(
            config: try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0),
            repository: repository, source: library, photoAccess: library,
            geocoder: geocoder, defaults: defaults, homeCountryCode: "TW", now: { [now] in now }
        )
        return Harness(
            model: model, library: library, geocoder: geocoder, repository: repository, defaults: defaults,
            database: database
        )
    }

    private func waitUntil(_ description: String, _ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), description)
    }

    /// **A stored trip keeps its own name on this list** (#164). The list drew
    /// the geocoded place over it, so a trip the person had named read "Japan"
    /// here and by its name on every other screen.
    func testAStoredTripIsCalledByItsOwnNameNotItsPlace() async throws {
        let harness = try makeHarness(photos: homeYear())
        let service = ImportService(repository: harness.repository, config: AppConfig.loadOrDie())
        // Enough photographs in each place to make it a stop: the place is
        // looked up at a stop, never anywhere else.
        var named: [ImportPhoto] = []
        for index in 0..<4 {
            let at = 10 * week + Double(index) * 1_800
            named.append(photo("n-tokyo-\(index)", at, 35.68, 139.65))
            named.append(photo("n-kyoto-\(index)", at + 86_400, 35.01, 135.77))
        }
        let tripId = try await service.importTrip(title: "北海道夏天", photos: named)

        await harness.model.refresh()
        await waitUntil("looked up") { harness.model.summary(forTrip: tripId)?.name != nil }

        let stored = try XCTUnwrap(harness.model.summary(forTrip: tripId))
        XCTAssertEqual(stored.name?.title, "Japan", "the place is known — it is what used to win")
        XCTAssertEqual(stored.headline, "北海道夏天")
        XCTAssertEqual(stored.name?.flag, "🇯🇵", "the flag still comes from the place")
    }

    /// **A journey opened before its place is known is not titled for good**
    /// (#165). The card's month title was stored as the trip's name, which
    /// `TripTitle` took for a name a person gave, so the trip stayed
    /// "September 2026". It is stored unnamed, looked up at once, and then
    /// called by flag and town (Chiu 2026-10-01).
    func testAJourneyOpenedBeforeItsNameIsKnownIsNamedWhenTheLookupAnswers() async throws {
        let harness = try makeHarness(photos: oneTownLibrary())
        let places = harness.geocoder.table
        harness.geocoder.table = []
        await harness.model.refresh()
        await waitUntil("asked, and not answered") { harness.geocoder.lookups == 1 }
        let card = try XCTUnwrap(harness.model.journeys.first)
        XCTAssertNil(card.name)

        harness.geocoder.table = places
        let opened = await harness.model.open(card)
        let tripId = try XCTUnwrap(opened)
        let trip = try XCTUnwrap(try harness.repository.detail(tripId: tripId)?.trip)
        XCTAssertTrue(TripTitle.isFallback(trip), "stored unnamed: \(trip.title)")

        let cache = JourneyNameCache(defaults: harness.defaults)
        await waitUntil("looked up without the queue") { cache.place(for: card.id) != nil }
        XCTAssertEqual(TripTitle.film(trip, cache: cache, homeCountryCode: "TW"), "🇨🇦 Whitehorse")
        await waitUntil("the card follows") { harness.model.summary(forTrip: tripId)?.headline == "Whitehorse" }
        XCTAssertEqual(
            harness.geocoder.askedLatitudes.filter { abs($0 - 60.72) < 0.5 }.count, 2,
            "the unanswered scan lookup, then one at the tap — the queue does not ask again"
        )
    }

    /// **A tap that makes no trip says why** (#166). The model logged the
    /// error and returned nil, and the screen stayed exactly as it was.
    func testAJourneyThatCannotBeStoredSaysSo() async throws {
        let harness = try makeHarness(photos: oneTownLibrary())
        await harness.model.refresh()
        let card = try XCTUnwrap(harness.model.journeys.first)
        // The photographs are fine; the store refuses them (`ImportSaveFailureTests`).
        try await harness.database.writer.write { try $0.execute(sql: "DROP TABLE photo_ref") }

        let opened = await harness.model.open(card)
        XCTAssertNil(opened)
        XCTAssertEqual(harness.model.openFailure, .saveFailed)
        XCTAssertNil(harness.model.openingId, "the card's spinner stops")

        harness.model.acknowledgeOpenFailure()
        XCTAssertNil(harness.model.openFailure)
    }
}

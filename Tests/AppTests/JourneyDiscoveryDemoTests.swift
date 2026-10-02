@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **A library whose photographs share a handful of asset ids** — the
/// `-demo-discover` library, which borrows the simulator's few images in
/// rotation (#178).
@MainActor
final class JourneyDiscoveryDemoTests: XCTestCase {
    private let week = 7.0 * 86_400
    private let now = Date(timeIntervalSince1970: 60 * 7 * 86_400)

    /// Home, then two journeys abroad. Every photograph carries one of three
    /// asset ids, as the demo's do.
    private func recycledLibrary() -> [ImportPhoto] {
        var next = 0
        func photo(_ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
            defer { next += 1 }
            return ImportPhoto(assetId: "shared-\(next % 3)", timestamp: ts, lat: lat, lon: lon)
        }
        var photos = (0..<52).map { photo(Double($0) * week - 3 * 3_600, 25.04, 121.56) }
        for index in 0..<6 {
            let at = Double(index) * 1_800
            photos.append(photo(10 * week + at, 35.68, 139.65))
            photos.append(photo(10 * week + 2 * 86_400 + at, 35.01, 135.77))
            photos.append(photo(30 * week + at, 60.72, -135.05))
            photos.append(photo(30 * week + 86_400 + at, 60.80, -135.20))
        }
        return photos
    }

    private func makeModel(matchesTripsByPhotographs: Bool) throws -> JourneyDiscoveryModel {
        let suite = "kamome.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let library = DiscoveryStubLibrary()
        library.photos = recycledLibrary()
        return JourneyDiscoveryModel(
            config: try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            source: library, photoAccess: library, geocoder: DiscoveryStubGeocoder(),
            defaults: defaults, homeCountryCode: "TW",
            matchesTripsByPhotographs: matchesTripsByPhotographs, now: { [now] in now }
        )
    }

    /// The demo's setting: one journey stored, and the other is still offered
    /// and still opens as itself.
    func testWithRecycledIdsEveryJourneyIsStillOfferedAndOpensAsItself() async throws {
        let model = try makeModel(matchesTripsByPhotographs: false)
        await model.refresh()
        XCTAssertEqual(model.journeys.count, 2)
        let newer = model.journeys[0], older = model.journeys[1]

        let firstOpened = await model.open(older)
        let firstTrip = try XCTUnwrap(firstOpened)
        await model.refresh()
        XCTAssertEqual(model.journeys.count, 2, "the stored trip, and the journey still to open")
        XCTAssertEqual(model.journeys.filter(\.isImported).map(\.id), [older.id])

        let found = try XCTUnwrap(model.journeys.first { $0.id == newer.id })
        let secondOpened = await model.open(found)
        let secondTrip = try XCTUnwrap(secondOpened)
        XCTAssertNotEqual(secondTrip, firstTrip, "the second journey is its own trip, not the first one again")
        await model.refresh()
        XCTAssertEqual(model.journeys.filter(\.isImported).count, 2)
    }

    /// The control, and the cause of #178: matched by photographs, as a real
    /// library is, the one stored trip claims the other journey — they hold
    /// the same ids. Correct for a real library, where shared ids mean shared
    /// photographs (ADR 2026-09-23 (d)).
    func testMatchedByPhotographsOneStoredTripClaimsEveryJourneySharingItsIds() async throws {
        let model = try makeModel(matchesTripsByPhotographs: true)
        await model.refresh()
        XCTAssertEqual(model.journeys.count, 2)

        let opened = await model.open(model.journeys[1])
        XCTAssertNotNil(opened)
        await model.refresh()
        XCTAssertEqual(model.journeys.count, 1, "the other journey is taken for a repeat of the stored trip")
    }
}

@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **The same photographs never silently make a second trip** (Chiu
/// 2026-09-23). Chiu's home showed "Vietnam" and 「🇻🇳 Vietnam」 over the same
/// dates: the import sheet never looked for an existing trip, and Discovery only
/// recognised trips carrying its own key. Both paths now ask
/// `TripRepository.tripHoldingMost`, whichever path made the first trip.
@MainActor
final class RepeatImportTests: XCTestCase {
    private final class StubLibrary: ImportPhotoProviding, PhotoAccessProviding {
        var photos: [ImportPhoto] = []
        func photos(matching query: ImportQuery) async -> [ImportPhoto] { photos }
        func albums() async -> [PhotoAlbum] { [] }
        var readAccess: PhotoReadAccess { .granted }
        func requestReadAccess() async -> PhotoReadAccess { .granted }
        func presentLimitedLibraryPicker(completion: @escaping () -> Void) { completion() }
    }

    private final class NoGeocoder: PlaceGeocoding {
        func place(lat: Double, lon: Double) async -> PlaceName? { nil }
    }

    private let week = 7.0 * 86_400
    private let now = Date(timeIntervalSince1970: 60 * 7 * 86_400)

    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// A year of weekly photographs at home, and one Tokyo → Kyoto journey.
    /// Home is photographed the evening before each week mark, never at it: a
    /// photograph at home ends a journey (R1, 2026-09-25), and one sharing the
    /// trip's first second would be ordered by asset id alone.
    private func library() -> [ImportPhoto] {
        var photos = (0..<52).map { photo("home-\($0)", Double($0) * week - 3 * 3_600, 25.04, 121.56) }
        photos += (0..<12).map { photo("jp-\($0)", 10 * week + Double($0) * 1_800, 35.68, 139.65) }
        photos += (0..<6).map { photo("kyoto-\($0)", 10 * week + 2 * 86_400 + Double($0) * 1_800, 35.01, 135.77) }
        return photos
    }

    private var japan: [ImportPhoto] { library().filter { !$0.assetId.hasPrefix("home") } }

    private func stored(_ repository: TripRepository, assetIds: [String]) throws -> String {
        let stop = TripRepository.NewStopWithPhotos(
            stop: TripRepository.NewStop(lat: 35.68, lon: 139.65, arrivedAt: 0, departedAt: 600),
            photos: assetIds.map { TripRepository.NewPhoto(assetId: $0) }
        )
        return try repository.saveImportedTrip(TripRepository.ImportedTrip(
            title: "Japan", startedAt: 0, endedAt: 600, source: TripSource.importedPhotos.rawValue,
            segments: [], stopsWithPhotos: [stop], routeAttachedPhotos: []
        ))
    }

    // MARK: - The lookup

    func testTheTripHoldingEnoughOfThePhotosIsFound() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let small = try stored(repository, assetIds: ["a", "b"])
        let big = try stored(repository, assetIds: ["c", "d", "e"])

        XCTAssertEqual(try repository.tripHoldingMost(assetIds: ["a", "c", "d", "e"], minShare: 0.5), big)
        XCTAssertEqual(try repository.tripHoldingMost(assetIds: ["a", "b", "x"], minShare: 0.5), small)
        XCTAssertNil(
            try repository.tripHoldingMost(assetIds: ["a", "x", "y", "z"], minShare: 0.5),
            "one shared photograph out of four is not the same journey"
        )
        XCTAssertNil(try repository.tripHoldingMost(assetIds: [], minShare: 0.5))
    }

    /// Past SQLite's bound-variable limit the lookup must still count every id.
    func testALongTripIsCountedAcrossChunks() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let ids = (0..<1_200).map { "p\($0)" }
        let trip = try stored(repository, assetIds: ids)
        let incoming = ids + (0..<1_000).map { "new\($0)" }
        XCTAssertEqual(try repository.tripHoldingMost(assetIds: incoming, minShare: 0.5), trip, "1200 of 2200")
        XCTAssertNil(try repository.tripHoldingMost(assetIds: incoming, minShare: 0.6))
    }

    // MARK: - The import sheet

    func testARepeatImportOffersTheTripThatExists() async throws {
        let library = StubLibrary()
        library.photos = japan
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let first = ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library)
        await first.runImport()
        let existing = try XCTUnwrap(first.completedTripId)

        let again = ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library)
        await again.runImport()
        guard case let .duplicate(duplicate) = again.phase else {
            return XCTFail("a repeat import must stop and ask, got \(again.phase)")
        }
        XCTAssertEqual(duplicate.tripId, existing)
        XCTAssertNil(again.completedTripId)
        XCTAssertEqual(try repository.allTrips().count, 1, "nothing is written before the user answers")

        again.openExisting()
        XCTAssertEqual(again.completedTripId, existing)
        XCTAssertEqual(try repository.allTrips().count, 1)
    }

    func testImportAnywayMakesTheSecondCopyTheUserAskedFor() async throws {
        let library = StubLibrary()
        library.photos = japan
        let repository = TripRepository(database: try AppDatabase.inMemory())
        await ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library).runImport()

        let again = ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library)
        await again.runImport()
        await again.importAnyway()
        XCTAssertNotNil(again.completedTripId)
        XCTAssertEqual(try repository.allTrips().count, 2)
    }

    func testChangingTheSelectionClearsTheVerdict() async throws {
        let library = StubLibrary()
        library.photos = japan
        let repository = TripRepository(database: try AppDatabase.inMemory())
        await ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library).runImport()

        let again = ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library)
        await again.runImport()
        again.selectionChanged()
        XCTAssertEqual(again.phase, .idle)
        await again.importAnyway()
        XCTAssertEqual(try repository.allTrips().count, 1, "the paused fetch went with the verdict")
    }

    // MARK: - Discovery

    /// The exact case on Chiu's home: imported through the sheet (no discovery
    /// key), then offered again by Discovery.
    func testDiscoveryDoesNotOfferAJourneyTheSheetAlreadyImported() async throws {
        let suite = "kamome.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let whole = StubLibrary()
        whole.photos = library()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let config = try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0)
        let sheet = StubLibrary()
        sheet.photos = japan
        let byHand = ImportFlowModel(config: config, repository: repository, source: sheet)
        await byHand.runImport()
        let existing = try XCTUnwrap(byHand.completedTripId)

        let model = JourneyDiscoveryModel(
            config: config, repository: repository, source: whole, photoAccess: whole,
            geocoder: NoGeocoder(), defaults: defaults, homeCountryCode: "TW", now: { [now] in now }
        )
        await model.refresh()

        XCTAssertEqual(model.journeys.count, 1, "the stored trip, not the trip and its twin")
        XCTAssertEqual(model.journeys.first?.tripId, existing)
    }
}

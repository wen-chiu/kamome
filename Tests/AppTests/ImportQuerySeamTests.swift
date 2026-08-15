@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **The import seam: which photographs a trip is built from** (spec §4.7, album
/// import 2026-08-15).
///
/// These drive `ImportFlowModel` over a stub source, so what is under test is the
/// query the model asks for and what it does with the answer — never PhotoKit,
/// which stays confined to `PhotoLibraryImportSource` and cannot run here.
///
/// The device check these cannot replace: import one real trip by album and
/// confirm the trip contains only that album's photographs.
@MainActor
final class ImportQuerySeamTests: XCTestCase {
    /// Records what it was asked for and answers from a fixed table.
    private final class StubSource: ImportPhotoProviding {
        var queries: [ImportQuery] = []
        var byAlbum: [String: [ImportPhoto]] = [:]
        var inRange: [ImportPhoto] = []
        var albumList: [PhotoAlbum] = []

        func photos(matching query: ImportQuery) async -> [ImportPhoto] {
            queries.append(query)
            switch query {
            case .dateRange: return inRange
            case let .album(id): return byAlbum[id] ?? []
            }
        }

        func albums() async -> [PhotoAlbum] { albumList }
    }

    private func photo(_ id: String, _ offsetS: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: 1_752_600_000 + offsetS, lat: lat, lon: lon)
    }

    /// Two clusters far enough apart to be separate stops, so the importer has a
    /// renderable trip.
    private func tripPhotos(prefix: String) -> [ImportPhoto] {
        [
            photo("\(prefix)-a1", 0, 63.4040, -19.0410),
            photo("\(prefix)-a2", 60, 63.4044, -19.0405),
            photo("\(prefix)-a3", 120, 63.4041, -19.0412),
            photo("\(prefix)-b1", 7_200, 63.5300, -19.5500),
            photo("\(prefix)-b2", 7_260, 63.5305, -19.5495),
            photo("\(prefix)-b3", 7_320, 63.5302, -19.5502)
        ]
    }

    private func makeModel(source: StubSource) throws -> ImportFlowModel {
        let config = AppConfig.loadOrDie()
        return ImportFlowModel(
            config: config,
            repository: TripRepository(database: try AppDatabase.inMemory()),
            source: source
        )
    }

    /// The default path is unchanged: no album chosen, a date range asked for.
    func testDateRangeRemainsTheDefaultQuery() async throws {
        let source = StubSource()
        source.inRange = tripPhotos(prefix: "range")
        let model = try makeModel(source: source)

        XCTAssertEqual(model.source, .dateRange)
        await model.runImport()

        XCTAssertNotNil(model.completedTripId)
        XCTAssertEqual(source.queries.count, 1)
        guard case .dateRange = try XCTUnwrap(source.queries.first) else {
            return XCTFail("expected a date-range query, got \(source.queries)")
        }
    }

    /// An album run asks for **that album**, and for nothing else — the property
    /// the device check confirms against a real library.
    func testAlbumRunAsksForThatAlbumOnly() async throws {
        let source = StubSource()
        source.inRange = tripPhotos(prefix: "range")
        source.byAlbum = ["album-2": tripPhotos(prefix: "album")]
        source.albumList = [
            PhotoAlbum(id: "album-1", title: "Other", photoCount: 3, earliest: .now, latest: .now),
            PhotoAlbum(id: "album-2", title: "Iceland", photoCount: 6, earliest: .now, latest: .now)
        ]
        let model = try makeModel(source: source)
        model.source = .album
        await model.loadAlbums()
        model.selectedAlbumId = "album-2"

        await model.runImport()

        XCTAssertNotNil(model.completedTripId)
        XCTAssertEqual(source.queries, [.album(id: "album-2")],
                       "the album run must not also fetch a date range")
    }

    /// An album with no geotagged photographs must fail **exactly** as an empty
    /// date range does — the same message, not a new dead end. Miyakojima's own
    /// folder was 53 geotagged files of 406, so this is the ordinary case.
    func testEmptyAlbumFailsTheSameWayAnEmptyRangeDoes() async throws {
        let emptyRange = StubSource()
        let rangeModel = try makeModel(source: emptyRange)
        await rangeModel.runImport()

        let emptyAlbum = StubSource()
        emptyAlbum.albumList = [
            PhotoAlbum(id: "empty", title: "Screenshots", photoCount: 4, earliest: .now, latest: .now)
        ]
        let albumModel = try makeModel(source: emptyAlbum)
        albumModel.source = .album
        await albumModel.loadAlbums()
        albumModel.selectedAlbumId = "empty"
        await albumModel.runImport()

        XCTAssertEqual(rangeModel.phase, .failed(.noGeotaggedPhotos))
        XCTAssertEqual(albumModel.phase, rangeModel.phase, "album and range must fail identically")
        XCTAssertNil(albumModel.completedTripId)
    }

    /// The album's name becomes the trip's title — the user already named this
    /// journey — while the date range keeps its date-shaped default.
    func testAlbumTitleBecomesTheTripTitle() async throws {
        let source = StubSource()
        source.byAlbum = ["a": tripPhotos(prefix: "album")]
        source.albumList = [
            PhotoAlbum(id: "a", title: "Iceland 2026", photoCount: 6, earliest: .now, latest: .now)
        ]
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let model = ImportFlowModel(config: config, repository: repository, source: source)
        model.source = .album
        await model.loadAlbums()
        model.selectedAlbumId = "a"

        await model.runImport()

        let tripId = try XCTUnwrap(model.completedTripId)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.trip.title, "Iceland 2026")
    }

    /// Nothing is imported until an album is chosen, and the sheet's button knows
    /// it — a `.album` run with no selection must not silently import the range.
    func testAlbumRunCannotStartWithoutASelection() async throws {
        let source = StubSource()
        source.inRange = tripPhotos(prefix: "range")
        let model = try makeModel(source: source)
        model.source = .album

        XCTAssertFalse(model.canImport)
        await model.runImport()

        XCTAssertTrue(source.queries.isEmpty, "no query may be issued without an album")
        XCTAssertNil(model.completedTripId)
        XCTAssertEqual(model.phase, .failed(.noGeotaggedPhotos))
    }

    /// A selection that disappears — the limited-library set changed, or the album
    /// was deleted — must not leave a stale id that would import nothing.
    func testAVanishedAlbumSelectionIsDropped() async throws {
        let source = StubSource()
        source.albumList = [
            PhotoAlbum(id: "a", title: "Iceland", photoCount: 6, earliest: .now, latest: .now)
        ]
        let model = try makeModel(source: source)
        model.source = .album
        await model.loadAlbums()
        model.selectedAlbumId = "a"

        source.albumList = []
        await model.loadAlbums()

        XCTAssertNil(model.selectedAlbumId)
        XCTAssertFalse(model.canImport)
    }
}

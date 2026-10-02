@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **An unnamed import is titled from its own first photograph** (#131). The
/// date-range path used to take the picked range's first day. The default range
/// is the last week, and a trip seldom starts on its first day, so the title
/// named a day the trip never saw. `TripTitle.isFallback` then read the trip as
/// named by the person, and the film never opened on its country (#108).
@MainActor
final class ImportTitleTests: XCTestCase {
    private final class StubLibrary: ImportPhotoProviding, PhotoAccessProviding {
        var photos: [ImportPhoto] = []
        var albumList: [PhotoAlbum] = []
        func photos(matching query: ImportQuery) async -> [ImportPhoto] { photos }
        func albums() async -> [PhotoAlbum] { albumList }
        var readAccess: PhotoReadAccess { .granted }
        func requestReadAccess() async -> PhotoReadAccess { .granted }
        func presentLimitedLibraryPicker(completion: @escaping () -> Void) { completion() }
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Tokyo → Kyoto, starting three days after the default range opens.
    private func journey() -> [ImportPhoto] {
        let start = now.timeIntervalSince1970 - 3 * 86_400
        var photos = (0..<12).map {
            ImportPhoto(assetId: "jp-\($0)", timestamp: start + Double($0) * 1_800, lat: 35.68, lon: 139.65)
        }
        photos += (0..<6).map {
            ImportPhoto(assetId: "kyoto-\($0)", timestamp: start + 86_400 + Double($0) * 1_800, lat: 35.01, lon: 135.77)
        }
        return photos
    }

    private func album(_ title: String) -> PhotoAlbum {
        PhotoAlbum(id: "a1", title: title, photoCount: 18, earliest: nil, latest: nil)
    }

    private func imported(source: ImportFlowModel.Source, album: PhotoAlbum? = nil) async throws -> TripRecord {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let library = StubLibrary()
        library.photos = journey()
        library.albumList = album.map { [$0] } ?? []
        let model = ImportFlowModel(config: AppConfig.loadOrDie(), repository: repository, source: library, now: now)
        model.source = source
        if let album {
            await model.loadAlbums()
            model.selectedAlbumId = album.id
        }
        await model.runImport()
        let tripId = try XCTUnwrap(model.completedTripId, "the import must succeed")
        return try XCTUnwrap(repository.detail(tripId: tripId)?.trip)
    }

    func testADateRangeImportIsTitledFromItsFirstPhotographNotTheRange() async throws {
        let trip = try await imported(source: .dateRange)
        let firstPhoto = try XCTUnwrap(journey().map(\.timestamp).min())

        // Restated 2026-10-02 (#168, Chiu: an unnamed trip is stored with no
        // title). This pinned the first photograph's date as the stored string;
        // the same date is now what the trip is called, read off its own start.
        XCTAssertEqual(trip.title, TripTitle.unnamed)
        XCTAssertEqual(TripTitle.plain(trip), TripTitle.fallback(for: firstPhoto))
        XCTAssertTrue(TripTitle.isFallback(trip), "nobody named it, so the film may open on its country")
    }

    func testAnUnnamedAlbumIsTitledTheSameWay() async throws {
        let trip = try await imported(source: .album, album: album(""))
        XCTAssertTrue(TripTitle.isFallback(trip))
    }

    func testANamedAlbumKeepsItsName() async throws {
        let trip = try await imported(source: .album, album: album("關西"))
        XCTAssertEqual(trip.title, "關西")
        XCTAssertFalse(TripTitle.isFallback(trip))
    }
}

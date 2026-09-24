@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **A trip the database refused is not "no geotagged photos"**
/// (arch review 2026-09-24, P1-5).
///
/// `ImportFlowModel.save` treated every thrown error as the importer's own
/// "not enough photos", so a storage failure told the user to go and fix their
/// photo library. The photos here are a renderable trip; only the save fails.
@MainActor
final class ImportSaveFailureTests: XCTestCase {
    private final class FixedSource: ImportPhotoProviding {
        let photos: [ImportPhoto]
        init(_ photos: [ImportPhoto]) { self.photos = photos }
        func photos(matching query: ImportQuery) async -> [ImportPhoto] { photos }
        func albums() async -> [PhotoAlbum] { [] }
    }

    private func photo(_ id: String, _ offsetS: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: 1_752_600_000 + offsetS, lat: lat, lon: lon)
    }

    func testAStorageFailureIsNotReportedAsMissingPhotos() async throws {
        let database = try AppDatabase.inMemory()
        // A table the import writes into is gone, so the save throws a database
        // error and nothing about the photographs is wrong.
        try await database.writer.write { try $0.execute(sql: "DROP TABLE photo_ref") }
        let model = ImportFlowModel(
            config: AppConfig.loadOrDie(),
            repository: TripRepository(database: database),
            source: FixedSource([
                photo("a1", 0, 63.4040, -19.0410), photo("a2", 60, 63.4044, -19.0405),
                photo("a3", 120, 63.4041, -19.0412), photo("b1", 7_200, 63.5300, -19.5500),
                photo("b2", 7_260, 63.5305, -19.5495), photo("b3", 7_320, 63.5302, -19.5502)
            ])
        )

        await model.runImport()

        XCTAssertEqual(model.phase, .failed(.saveFailed))
        XCTAssertNil(model.completedTripId)
    }
}

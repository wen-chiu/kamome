@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **S3 rename** (Chiu 2026-09-27): the person names the trip from Trip
/// Detail's edit menu. Home, Trip Detail and the film all read the one stored
/// title, so the rename is what they show.
@MainActor
final class TripRenameTests: XCTestCase {
    private func importedModel(title: String) async throws -> TripDetailModel {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let start = 1_787_382_000.0
        let photos = [
            ImportPhoto(assetId: "a", timestamp: start, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "b", timestamp: start + 60, lat: 64.0, lon: -20.0)
        ]
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: title, photos: photos)
        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        model.reload()
        return model
    }

    func testRenameStoresTheTrimmedName() async throws {
        let model = try await importedModel(title: "Sep 20, 2026")
        model.renameTrip(to: "  北海道夏天 \n")
        XCTAssertEqual(model.detail?.trip.title, "北海道夏天")
    }

    func testAnEmptyNameChangesNothing() async throws {
        let model = try await importedModel(title: "Iceland ring road")
        model.renameTrip(to: "   ")
        XCTAssertEqual(model.detail?.trip.title, "Iceland ring road",
                       "an empty title would open the film on a blank card")
    }

    /// The story screen used to put the cached place above the stored title,
    /// so a rename never showed there.
    func testTheStoryShowsTheRenamedTitle() async throws {
        let model = try await importedModel(title: "Iceland ring road")
        model.renameTrip(to: "Ring road with Mum")
        XCTAssertEqual(model.storyTitle, "Ring road with Mum")
    }
}

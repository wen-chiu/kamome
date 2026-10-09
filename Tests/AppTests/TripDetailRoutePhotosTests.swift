@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **A route photograph can be taken off the trip** (Chiu 2026-10-09). The
/// strip stops showing it; the sheet still lists it so it can be put back; and
/// the row is marked, never deleted, so a re-match cannot bring it back.
@MainActor
final class TripDetailRoutePhotosTests: XCTestCase {
    func testARemovedRoutePhotoLeavesTheStripAndComesBack() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let start = 1_787_382_000.0
        // Lone photographs well beyond `stop_radius_m` of each other are
        // route-attached; the pair is a stop.
        let photos = [
            ImportPhoto(assetId: "stop-a", timestamp: start, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "stop-b", timestamp: start + 60, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "route1", timestamp: start + 3_600, lat: 64.5, lon: -20.0),
            ImportPhoto(assetId: "route2", timestamp: start + 7_200, lat: 65.0, lon: -20.0)
        ]
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: "route", photos: photos)
        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        await model.refresh()
        XCTAssertEqual(Set(model.shownRoutePhotos.map(\.phAssetId)), ["route1", "route2"])

        let route1 = try XCTUnwrap(model.routePhotos.first { $0.phAssetId == "route1" })
        model.setRemovedFromTrip(route1, removed: true)
        await model.refresh()
        XCTAssertEqual(model.shownRoutePhotos.map(\.phAssetId), ["route2"], "the strip no longer shows it")
        XCTAssertEqual(Set(model.routePhotos.map(\.phAssetId)), ["route1", "route2"], "the sheet still lists it")
        XCTAssertEqual(try repository.photoRefs(tripId: tripId).count, 4, "marked, not deleted")

        model.setRemovedFromTrip(route1, removed: false)
        await model.refresh()
        XCTAssertEqual(Set(model.shownRoutePhotos.map(\.phAssetId)), ["route1", "route2"])
    }
}

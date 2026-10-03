@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **S3's day chips** (Chiu 2026-09-25): a chip is a calendar date, and the
/// "Along the route" strip shows that date's photographs only. The Japan import
/// showed the whole trip's five route photographs under every chip, and its
/// 8/26 stops under Day 4 because the trip began in the afternoon.
@MainActor
final class TripDetailDaysTests: XCTestCase {
    func testAChipHoldsItsOwnDatesStopsAndRoutePhotographs() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        // 15:00 local on some day: the start's hour is what made 24-hour blocks wrong.
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_787_382_000))
        let start = firstDay.timeIntervalSince1970 + 15 * 3_600
        let nextMorning = start + 18 * 3_600 // 09:00 on the second date
        // Each group sits well beyond `stop_radius_m` of the others: pairs are
        // stops, lone photographs are route-attached.
        let photos = [
            ImportPhoto(assetId: "stop1-a", timestamp: start, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "stop1-b", timestamp: start + 60, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "route1", timestamp: start + 3_600, lat: 64.5, lon: -20.0),
            ImportPhoto(assetId: "route2", timestamp: nextMorning, lat: 65.0, lon: -20.0),
            ImportPhoto(assetId: "stop2-a", timestamp: nextMorning + 3_600, lat: 65.5, lon: -20.0),
            ImportPhoto(assetId: "stop2-b", timestamp: nextMorning + 3_660, lat: 65.5, lon: -20.0)
        ]
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: "days", photos: photos)

        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        await model.refresh()
        XCTAssertEqual(model.dayCount, 2)
        XCTAssertEqual(Set(model.routePhotos.map(\.phAssetId)), ["route1", "route2"], "All shows every route photo")

        model.selectDay(1)
        XCTAssertEqual(model.visibleStops.map(\.arrivedAt), [nextMorning + 3_600],
                       "18 h after the start is the second date, not the first 24-hour block")
        XCTAssertEqual(model.routePhotos.map(\.phAssetId), ["route2"])

        model.selectDay(0)
        XCTAssertEqual(model.visibleStops.map(\.arrivedAt), [start])
        XCTAssertEqual(model.routePhotos.map(\.phAssetId), ["route1"])
    }

    /// **A stop's row shows the time where the stop is** (ADR 2026-10-01).
    /// Two stops in zones five hours apart, so whatever zone this machine is
    /// in, the phone's clock cannot give both answers.
    func testAStopsRowShowsTheTimeWhereTheStopIs() async throws {
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let taipeiEvening = 1_769_954_400.0 // 2026-02-01 22:00 in Taipei (UTC+8)
        let aucklandAfternoon = taipeiEvening + 12 * 3_600 // 2026-02-02 15:00 in Auckland (UTC+13)
        let photos = [
            ImportPhoto(assetId: "a1", timestamp: taipeiEvening, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "a2", timestamp: taipeiEvening + 60, lat: 64.0, lon: -20.0),
            ImportPhoto(assetId: "b1", timestamp: aucklandAfternoon, lat: 65.5, lon: -20.0),
            ImportPhoto(assetId: "b2", timestamp: aucklandAfternoon + 60, lat: 65.5, lon: -20.0)
        ]
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: "zones", photos: photos)
        // Named, with a town, a zone and its part of town ("" = asked, none):
        // the model's own geocoder has nothing to ask.
        let stored = try XCTUnwrap(try repository.detail(tripId: tripId)).stops
        XCTAssertEqual(stored.count, 2)
        for (stop, zone) in zip(stored, ["Asia/Taipei", "Pacific/Auckland"]) {
            try repository.setStopName(stopId: stop.id, name: "Stop")
            try repository.setStopLocality(stopId: stop.id, locality: "Town")
            try repository.setStopTimeZone(stopId: stop.id, timeZone: zone)
            try repository.setStopSubLocality(stopId: stop.id, subLocality: "")
        }

        let model = TripDetailModel(tripId: tripId, config: config, repository: repository)
        await model.refresh()
        let british = Locale(identifier: "en_GB")
        XCTAssertEqual(model.visibleStops.map { model.arrivalTime(of: $0, locale: british) }, ["22:00", "15:00"])
    }
}

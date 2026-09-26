@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **A stop keeps the zone its lookup reported** (schema v14, arch review
/// 2026-09-26): the same one lookup that names it, so nothing new leaves the
/// phone, and `TripClock` counts its day in the zone it happened in.
@MainActor
final class StopNamerTimeZoneTests: XCTestCase {
    private final class ZoneGeocoder: StopGeocoding {
        let zone: String?
        init(zone: String?) { self.zone = zone }

        func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
            reverseGeocodeZoned(lat: lat, lon: lon) { name, _, _, error in completion(name, error) }
        }

        func reverseGeocodeZoned(
            lat: Double, lon: Double, completion: @escaping (String?, String?, String?, Error?) -> Void
        ) {
            let zone = self.zone
            DispatchQueue.main.async { completion("Geocoded \(lat)", "Town", zone, nil) }
        }
    }

    private func importedTrip(config: TrackingConfig) async throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        var photos: [ImportPhoto] = []
        for index in 0..<2 {
            let time = Double(index) * (config.photoImport.stopSplitGapS + 600)
            let lat = 64.0 + Double(index) * 0.5
            photos.append(ImportPhoto(assetId: "s\(index)-a", timestamp: time, lat: lat, lon: -20.0))
            photos.append(ImportPhoto(assetId: "s\(index)-b", timestamp: time + 60, lat: lat, lon: -20.0))
        }
        let service = ImportService(repository: repository, config: config)
        return (repository, try await service.importTrip(title: "zones", photos: photos))
    }

    private func stops(_ repository: TripRepository, _ tripId: String) throws -> [StopRecord] {
        try XCTUnwrap(try repository.detail(tripId: tripId)).stops
    }

    private func namer(_ repository: TripRepository, zone: String?) -> StopNamer {
        StopNamer(
            config: TrackingConfig.Geocode(minIntervalS: 0.01, cachePrecisionDeg: 0.001),
            repository: repository, geocoder: ZoneGeocoder(zone: zone)
        )
    }

    func testNamingAStopRecordsItsZone() async throws {
        let (repository, tripId) = try await importedTrip(config: AppConfig.loadOrDie())
        let namer = namer(repository, zone: "Atlantic/Reykjavik")
        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(try stops(repository, tripId)) { if $0.isFinished { done.fulfill() } }
        await fulfillment(of: [done], timeout: 10)

        let named = try stops(repository, tripId)
        XCTAssertTrue(named.allSatisfy { $0.timeZone == "Atlantic/Reykjavik" }, "\(named.map(\.timeZone))")
        XCTAssertEqual(TripClock(stops: named, fallback: TimeZone(identifier: "Asia/Taipei")!)
            .zone(at: named[0].arrivedAt).identifier, "Atlantic/Reykjavik")
    }

    func testAStopNamedBeforeZonesGetsItsZoneAndKeepsItsName() async throws {
        let (repository, tripId) = try await importedTrip(config: AppConfig.loadOrDie())
        for stop in try stops(repository, tripId) {
            try repository.setStopName(stopId: stop.id, name: "My café")
            try repository.setStopLocality(stopId: stop.id, locality: "Selfoss")
        }
        XCTAssertTrue(try stops(repository, tripId).allSatisfy(StopNamer.needsLocality),
                      "a stop with a town but no zone must be asked once more")
        let namer = namer(repository, zone: "Atlantic/Reykjavik")

        namer.fillMissingLocalities(try stops(repository, tripId))
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let filled = try stops(repository, tripId)
        XCTAssertTrue(filled.allSatisfy { $0.name == "My café" }, "a zone lookup rewrote a name")
        XCTAssertTrue(filled.allSatisfy { $0.timeZone == "Atlantic/Reykjavik" }, "\(filled.map(\.timeZone))")
        XCTAssertTrue(filled.allSatisfy { !StopNamer.needsLocality($0) })
    }
}

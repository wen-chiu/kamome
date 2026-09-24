@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **Every stop learns its town, and no name is ever rewritten to get it**
/// (ADR 2026-09-24 (e)): the town feeds the film's HUD pill. A stop named before
/// schema v9 is asked for its town alone — its name may be the user's own.
final class StopNamerLocalityTests: XCTestCase {
    /// Answers a fixed name and town for every coordinate, on the main queue.
    private final class TownGeocoder: StopGeocoding {
        let town: String?
        private(set) var lookups = 0

        init(town: String?) { self.town = town }

        func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
            reverseGeocodePlace(lat: lat, lon: lon) { name, _, error in completion(name, error) }
        }

        func reverseGeocodePlace(
            lat: Double, lon: Double, completion: @escaping (String?, String?, Error?) -> Void
        ) {
            lookups += 1
            let town = self.town
            DispatchQueue.main.async { completion("Geocoded \(lat)", town, nil) }
        }
    }

    /// Two stops far apart, straight out of the real importer, all unnamed.
    private func importedTrip(config: TrackingConfig) async throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)
        var photos: [ImportPhoto] = []
        for index in 0..<2 {
            let time = Double(index) * (config.photoImport.stopSplitGapS + 600)
            let lat = 64.0 + Double(index) * 0.5
            photos.append(ImportPhoto(assetId: "s\(index)-a", timestamp: time, lat: lat, lon: -20.0))
            photos.append(ImportPhoto(assetId: "s\(index)-b", timestamp: time + 60, lat: lat, lon: -20.0))
        }
        return (repository, try await service.importTrip(title: "towns", photos: photos))
    }

    private func stops(_ repository: TripRepository, _ tripId: String) throws -> [StopRecord] {
        try XCTUnwrap(try repository.detail(tripId: tripId)).stops
    }

    /// Town-only work is not in `progress`, so there is nothing to wait on but
    /// time: two stops, a 10 ms throttle, and a stub that answers next turn.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func testNamingAStopAlsoRecordsItsTown() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, tripId) = try await importedTrip(config: config)
        let geocoder = TownGeocoder(town: "Reykjavík")
        let namer = StopNamer(
            config: TrackingConfig.Geocode(minIntervalS: 0.01, cachePrecisionDeg: 0.001),
            repository: repository, geocoder: geocoder
        )
        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(try stops(repository, tripId)) { progress in
            if progress.isFinished { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 10)
        let named = try stops(repository, tripId)
        XCTAssertTrue(named.allSatisfy { $0.locality == "Reykjavík" }, "\(named.map(\.locality))")
    }

    func testAStopNamedBeforeTownsGetsItsTownAndKeepsItsName() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, tripId) = try await importedTrip(config: config)
        for stop in try stops(repository, tripId) {
            try repository.setStopName(stopId: stop.id, name: "My café")
        }
        let geocoder = TownGeocoder(town: "Selfoss")
        let namer = StopNamer(
            config: TrackingConfig.Geocode(minIntervalS: 0.01, cachePrecisionDeg: 0.001),
            repository: repository, geocoder: geocoder
        )
        namer.fillMissingLocalities(try stops(repository, tripId))
        await settle()
        let filled = try stops(repository, tripId)
        XCTAssertTrue(filled.allSatisfy { $0.name == "My café" }, "a town lookup rewrote a name")
        XCTAssertTrue(filled.allSatisfy { $0.locality == "Selfoss" }, "\(filled.map(\.locality))")
        XCTAssertEqual(namer.progress.total, 0, "towns never hold the export gate")
    }

    func testAStopWithNoTownIsAskedOnce() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, tripId) = try await importedTrip(config: config)
        for stop in try stops(repository, tripId) {
            try repository.setStopName(stopId: stop.id, name: "Open sea")
        }
        let namer = StopNamer(
            config: TrackingConfig.Geocode(minIntervalS: 0.01, cachePrecisionDeg: 0.001),
            repository: repository, geocoder: TownGeocoder(town: nil)
        )
        namer.fillMissingLocalities(try stops(repository, tripId))
        await settle()
        let asked = try stops(repository, tripId)
        XCTAssertTrue(asked.allSatisfy { $0.locality == "" }, "\(asked.map(\.locality))")
        XCTAssertTrue(asked.allSatisfy { !StopNamer.needsLocality($0) }, "an empty answer is still an answer")
    }
}

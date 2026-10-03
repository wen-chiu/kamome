@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import XCTest

/// **A stop keeps the part of its town its lookup reported** (schema v15, #183,
/// ADR file 2026-10-02): from the same one lookup that names it, so nothing new
/// leaves the phone, and a film that never leaves one town can say where in it.
@MainActor
final class StopNamerSubLocalityTests: XCTestCase {
    private final class PartGeocoder: StopGeocoding {
        let part: String?
        private(set) var asked = 0
        init(part: String?) { self.part = part }

        func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
            reverseGeocodeStop(lat: lat, lon: lon) { place, error in completion(place.name, error) }
        }

        func reverseGeocodeStop(lat: Double, lon: Double, completion: @escaping (StopPlace, Error?) -> Void) {
            asked += 1
            let place = StopPlace(name: "Geocoded \(lat)", locality: "Town", subLocality: part, timeZone: "Asia/Tokyo")
            DispatchQueue.main.async { completion(place, nil) }
        }
    }

    private func importedTrip() async throws -> (TripRepository, String) {
        let config = try AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        var photos: [ImportPhoto] = []
        for index in 0..<2 {
            let time = Double(index) * (config.photoImport.stopSplitGapS + 600)
            let lat = 24.7 + Double(index) * 0.05
            photos.append(ImportPhoto(assetId: "s\(index)-a", timestamp: time, lat: lat, lon: 125.3))
            photos.append(ImportPhoto(assetId: "s\(index)-b", timestamp: time + 60, lat: lat, lon: 125.3))
        }
        let service = ImportService(repository: repository, config: config)
        return (repository, try await service.importTrip(title: "parts", photos: photos))
    }

    private func stops(_ repository: TripRepository, _ tripId: String) throws -> [StopRecord] {
        try XCTUnwrap(try repository.detail(tripId: tripId)).stops
    }

    private func namer(_ repository: TripRepository, _ geocoder: StopGeocoding) -> StopNamer {
        StopNamer(
            config: TrackingConfig.Geocode(minIntervalS: 0.01, cachePrecisionDeg: 0.001),
            repository: repository, geocoder: geocoder
        )
    }

    func testNamingAStopRecordsThePartOfItsTown() async throws {
        let (repository, tripId) = try await importedTrip()
        let namer = namer(repository, PartGeocoder(part: "Hirara"))
        let done = expectation(description: "naming finished")
        namer.nameUnnamedStops(try stops(repository, tripId)) { if $0.isFinished { done.fulfill() } }
        await fulfillment(of: [done], timeout: 10)

        let named = try stops(repository, tripId)
        XCTAssertTrue(named.allSatisfy { $0.subLocality == "Hirara" }, "\(named.map(\.subLocality))")
        XCTAssertTrue(named.allSatisfy { !StopNamer.needsLocality($0) })
    }

    /// A stop named before schema v15 has its town and zone and no part. It is
    /// asked once more, its name is not touched, and a town with no part here
    /// is recorded as asked, so the next open does not ask again.
    func testAStopNamedBeforePartsIsAskedOnceAndKeepsItsName() async throws {
        let (repository, tripId) = try await importedTrip()
        for stop in try stops(repository, tripId) {
            try repository.setStopName(stopId: stop.id, name: "My café")
            try repository.setStopLocality(stopId: stop.id, locality: "Town")
            try repository.setStopTimeZone(stopId: stop.id, timeZone: "Asia/Tokyo")
        }
        XCTAssertTrue(try stops(repository, tripId).allSatisfy(StopNamer.needsLocality),
                      "a stop with a town and no part must be asked once more")
        let geocoder = PartGeocoder(part: nil)
        let namer = namer(repository, geocoder)
        namer.fillMissingLocalities(try stops(repository, tripId))
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let filled = try stops(repository, tripId)
        XCTAssertTrue(filled.allSatisfy { $0.name == "My café" }, "a lookup for the part rewrote a name")
        XCTAssertTrue(filled.allSatisfy { $0.subLocality == "" }, "\(filled.map(\.subLocality))")
        XCTAssertTrue(filled.allSatisfy { !StopNamer.needsLocality($0) })
        let asked = geocoder.asked
        namer.fillMissingLocalities(filled)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(geocoder.asked, asked, "a stop already asked for its part was asked again")
    }
}

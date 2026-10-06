@testable import Kamome
import KamomeImportKit
import KamomePersistence
import XCTest

/// **One lookup per stop, ever** (Footprints ADR draft 2026-09-30, Data 3 and
/// "Tests owed"). A found journey's places are named while its preview is
/// open; 「新增旅程」 writes those answers onto the new stops, so S3 has
/// nothing left to ask. Leaving the preview stops asking.
@MainActor
final class PreviewStopNamerTests: XCTestCase {
    /// Counts every lookup and names a stop after its latitude.
    private final class CountingGeocoder: StopGeocoding {
        private(set) var asked: [Double] = []

        func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
            reverseGeocodeStop(lat: lat, lon: lon) { completion($0.name, $1) }
        }

        func reverseGeocodeStop(lat: Double, lon: Double, completion: @escaping (StopPlace, Error?) -> Void) {
            asked.append(lat)
            let place = StopPlace(
                name: "Place \(Int(lat * 100))", locality: "Town", subLocality: "Ward",
                timeZone: "Asia/Tokyo", countryCode: "JP"
            )
            DispatchQueue.main.async { completion(place, nil) }
        }
    }

    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// Invented places: three stops over three days.
    private func photos() -> [ImportPhoto] {
        let start = 1_780_000_000.0
        var photos: [ImportPhoto] = (0..<8).map { photo("a-\($0)", start + Double($0) * 600, 35.68, 139.65) }
        photos += (0..<6).map { photo("b-\($0)", start + 86_400 + Double($0) * 600, 35.01, 135.77) }
        photos += (0..<5).map { photo("c-\($0)", start + 2 * 86_400 + Double($0) * 600, 34.69, 135.50) }
        return photos
    }

    private func waitFor(_ description: String, _ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), description)
    }

    func testAPreviewsAnswersAreWrittenOntoTheNewTripsStopsAndNeverAskedAgain() async throws {
        let config = try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0)
        let geocoder = CountingGeocoder()
        let namer = PreviewStopNamer(geocoder: geocoder)
        let photos = photos()
        let plan = PhotoImportClusterer.plan(photos: photos, config: ImportService.clustering(config))
        let preview = JourneyItinerary(plan: plan, config: config)

        namer.name(preview.places) {}
        await waitFor("all three named") { namer.named(preview).places.allSatisfy { $0.name != nil } }
        XCTAssertEqual(geocoder.asked.count, 3, "one lookup per stop")

        // Opened again in the same session: nothing new is asked.
        namer.name(preview.places) {}
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(geocoder.asked.count, 3, "an answer is kept for the session")

        // 「新增旅程」 stores the plan and writes the answers onto its stops.
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: nil, photos: photos, plan: plan)
        namer.write(to: try XCTUnwrap(repository.detail(tripId: tripId)).stops, repository: repository)

        let stops = try XCTUnwrap(repository.detail(tripId: tripId)).stops
        XCTAssertEqual(stops.map(\.name), ["Place 3568", "Place 3501", "Place 3469"])
        XCTAssertEqual(Set(stops.map(\.locality)), ["Town"])
        XCTAssertEqual(Set(stops.map(\.timeZone)), ["Asia/Tokyo"])
        XCTAssertEqual(Set(stops.map(\.subLocality)), ["Ward"])
        XCTAssertEqual(Set(stops.map(\.countryCode)), ["JP"])
        XCTAssertTrue(
            stops.allSatisfy { !StopNamer.needsName($0) && !StopNamer.needsLocality($0) },
            "S3's namer has nothing left to ask Apple"
        )

        // The preview counts in the zones its lookups found, as S3 will: the
        // same hour and the same day. Found on the 2026-10-06 render, where the
        // preview said 6:00 PM (the phone's zone) and S3 said 7:00 PM (Tokyo).
        let named = namer.named(JourneyItinerary(plan: plan, config: config, clock: namer.clock(for: plan)))
        let stored = JourneyItinerary(detail: try XCTUnwrap(repository.detail(tripId: tripId)))
        XCTAssertEqual(named.places.map { named.arrivalTime(of: $0) }, stored.places.map { stored.arrivalTime(of: $0) })
        XCTAssertEqual(named.days.map(\.index), stored.days.map(\.index))
        XCTAssertEqual(named.places.map(\.name), stored.places.map(\.name))
    }

    func testLeavingThePreviewStopsAsking() async throws {
        let config = try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0)
        let geocoder = CountingGeocoder()
        let namer = PreviewStopNamer(geocoder: geocoder)
        let plan = PhotoImportClusterer.plan(photos: photos(), config: ImportService.clustering(config))
        let preview = JourneyItinerary(plan: plan, config: config)

        namer.name(preview.places) { namer.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(geocoder.asked.count, 1, "cancelled after the first answer: the rest are never asked")
    }

    /// A name someone typed is never replaced by a preview's answer.
    func testAStopThatHasANameKeepsIt() async throws {
        let config = try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0)
        let geocoder = CountingGeocoder()
        let namer = PreviewStopNamer(geocoder: geocoder)
        let photos = photos()
        let plan = PhotoImportClusterer.plan(photos: photos, config: ImportService.clustering(config))
        let preview = JourneyItinerary(plan: plan, config: config)
        namer.name(preview.places) {}
        await waitFor("named") { namer.named(preview).places.allSatisfy { $0.name != nil } }

        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: config)
            .importTrip(title: nil, photos: photos, plan: plan)
        let first = try XCTUnwrap(repository.detail(tripId: tripId)).stops[0]
        try repository.setStopName(stopId: first.id, name: "Typed")
        namer.write(to: try XCTUnwrap(repository.detail(tripId: tripId)).stops, repository: repository)

        XCTAssertEqual(try XCTUnwrap(repository.detail(tripId: tripId)).stops[0].name, "Typed")
    }
}

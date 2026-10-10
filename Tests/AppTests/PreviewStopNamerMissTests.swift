@testable import Kamome
import KamomeImportKit
import XCTest

/// **A place the lookup cannot name stops saying it is being identified**
/// (#264). The diary drew 「正在辨識這個地方…」 for every unnamed place,
/// including one whose lookup had already answered nothing, and asked again
/// each time the preview was opened.
@MainActor
final class PreviewStopNamerMissTests: XCTestCase {
    /// Names every stop but the one at `nameless`; answers only when told to,
    /// so a test can look at the run while a lookup is out.
    private final class GatedGeocoder: StopGeocoding {
        let nameless: Double
        private(set) var asked: [Double] = []
        private var held: [() -> Void] = []

        init(nameless: Double) { self.nameless = nameless }

        func reverseGeocode(lat: Double, lon: Double, completion: @escaping (String?, Error?) -> Void) {
            reverseGeocodeStop(lat: lat, lon: lon) { completion($0.name, $1) }
        }

        func reverseGeocodeStop(lat: Double, lon: Double, completion: @escaping (StopPlace, Error?) -> Void) {
            asked.append(lat)
            let name = lat == nameless ? nil : "Place \(Int(lat * 100))"
            held.append { completion(StopPlace(name: name), nil) }
        }

        /// Answers the lookup that is out, if any.
        func answer() -> Bool {
            guard !held.isEmpty else { return false }
            held.removeFirst()()
            return true
        }
    }

    private func photo(_ id: String, _ ts: Double, _ lat: Double, _ lon: Double) -> ImportPhoto {
        ImportPhoto(assetId: id, timestamp: ts, lat: lat, lon: lon)
    }

    /// Invented places: two stops on two days.
    private func preview() throws -> JourneyItinerary {
        let config = try JourneyDiscoveryModelTests.shippedConfig(geocodeInterval: 0)
        let start = 1_780_000_000.0
        var photos: [ImportPhoto] = (0..<8).map { photo("a-\($0)", start + Double($0) * 600, 35.68, 139.65) }
        photos += (0..<6).map { photo("b-\($0)", start + 86_400 + Double($0) * 600, 35.01, 135.77) }
        let plan = PhotoImportClusterer.plan(photos: photos, config: ImportService.clustering(config))
        return JourneyItinerary(plan: plan, photos: photos, config: config)
    }

    private func waitFor(_ description: String, _ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), description)
    }

    func testAPlaceWithNoAnswerStopsNamingAndIsNotAskedAgain() async throws {
        let preview = try preview()
        let places = preview.places
        XCTAssertEqual(places.count, 2)
        let geocoder = GatedGeocoder(nameless: places[1].lat)
        let namer = PreviewStopNamer(geocoder: geocoder)
        var changes = 0

        namer.name(places) { changes += 1 }
        XCTAssertTrue(places.allSatisfy(namer.isNaming), "both queued: both are being identified")

        await waitFor("the first lookup is out") { geocoder.asked.count == 1 }
        XCTAssertTrue(geocoder.answer())
        await waitFor("the first is named") { namer.named(preview).places[0].name != nil }
        XCTAssertFalse(namer.isNaming(places[0]))
        XCTAssertTrue(namer.isNaming(places[1]), "the second is still out")

        await waitFor("the second lookup is out") { geocoder.asked.count == 2 }
        XCTAssertTrue(geocoder.answer())
        await waitFor("a miss is told to the screen too") { changes == 2 }
        XCTAssertNil(namer.named(preview).places[1].name)
        XCTAssertFalse(namer.isNaming(places[1]), "no answer: no longer drawn as identifying")

        // Opened again this session: the miss is not asked again.
        namer.name(places) {}
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(geocoder.asked.count, 2)
        XCTAssertFalse(places.contains(where: namer.isNaming))
    }

    func testLeavingThePreviewLeavesNothingNaming() async throws {
        let preview = try preview()
        let namer = PreviewStopNamer(geocoder: GatedGeocoder(nameless: 0))
        namer.name(preview.places) {}
        XCTAssertTrue(preview.places.contains(where: namer.isNaming))
        namer.cancel()
        XCTAssertFalse(preview.places.contains(where: namer.isNaming))
    }
}

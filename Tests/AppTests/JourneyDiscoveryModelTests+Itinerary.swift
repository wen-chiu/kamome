@testable import Kamome
import XCTest

/// **What the diary will draw for a card** (Footprints ADR draft, Data 1): a
/// found journey's plan before 「新增旅程」, the stored trip after, and the
/// same places either way. Its own file: the test class body is held to 250
/// lines under SwiftLint.
extension JourneyDiscoveryModelTests {
    func testACardsItineraryIsItsPlanThenItsStoredTrip() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let japan = try XCTUnwrap(harness.model.journeys.last)
        let preview = try XCTUnwrap(harness.model.itinerary(for: japan))
        XCTAssertFalse(preview.isStored, "a found journey is previewed, not stored")
        XCTAssertEqual(preview.places.count, japan.stopCount, "the card counts the plan the diary draws")
        XCTAssertEqual(try harness.repository.allTrips().count, 0, "drawing it stores nothing")

        let opened = await harness.model.open(japan)
        let tripId = try XCTUnwrap(opened)
        let stored = try XCTUnwrap(harness.model.journeys.first { $0.tripId == tripId })
        let itinerary = try XCTUnwrap(harness.model.itinerary(for: stored))
        XCTAssertEqual(itinerary.tripId, tripId)
        XCTAssertEqual(itinerary.places.map(\.arrivedAt), preview.places.map(\.arrivedAt))
        XCTAssertEqual(itinerary.places.map(\.photoAssetIds), preview.places.map(\.photoAssetIds))
    }
}

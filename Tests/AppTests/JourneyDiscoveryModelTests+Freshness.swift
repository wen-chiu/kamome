@testable import Kamome
import KamomeImportKit
import XCTest

/// **The list as Footprints reads it again** — every time it is shown, with
/// no rescan (`loadTrips`). Its own file because the test class body is held
/// to 250 lines under SwiftLint; the harness is the class's own.
extension JourneyDiscoveryModelTests {
    /// #262 (1): photographs imported through the sheet after a scan are one
    /// journey, not two. The scan's photograph match used to be the only one,
    /// so coming back from Journeys listed the found journey beside its trip.
    func testAJourneyImportedThroughTheSheetIsNotListedTwice() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        XCTAssertEqual(harness.model.journeys.count, 2)

        let japan = harness.library.photos.filter { $0.assetId.hasPrefix("jp-") || $0.assetId.hasPrefix("kyoto-") }
        let tripId = try await ImportService(repository: harness.repository, config: harness.model.config)
            .importTrip(title: "Album", photos: japan)
        harness.model.loadTrips()

        XCTAssertEqual(harness.model.journeys.count, 2, "the trip, not the trip and its journey")
        XCTAssertTrue(harness.model.journeys.contains { $0.tripId == tripId })
        XCTAssertEqual(harness.model.journeys.filter { !$0.isImported }.count, 1, "only the other journey is found")
    }

    /// #262 (2): a trip made here and deleted in Journeys gives its journey
    /// back. It used to vanish from Footprints until a pull-to-refresh.
    func testADeletedTripGivesItsJourneyBack() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let japan = try XCTUnwrap(harness.model.journeys.last)
        let opened = await harness.model.open(japan)
        let tripId = try XCTUnwrap(opened)

        XCTAssertTrue(TripDeletion.delete(tripId: tripId, repository: harness.repository), "deleted in Journeys")
        harness.model.loadTrips()

        XCTAssertEqual(harness.model.journeys.count, 2)
        let found = try XCTUnwrap(harness.model.journeys.first { $0.id == japan.id }, "offered again")
        XCTAssertNil(found.tripId)
        let again = await harness.model.open(found)
        XCTAssertNotNil(again, "and it can be made into a trip again")
        XCTAssertNotEqual(again, tripId)
    }

    /// #263: a lookup that answers nothing is not asked again each time the
    /// list is read — four lookups for one stop point in three returns to
    /// Footprints, before. The entry stops showing that a name is coming, and
    /// only the person's own pull-to-refresh asks once more.
    func testALookupThatAnswersNothingIsAskedOncePerSession() async throws {
        let harness = try makeHarness()
        harness.geocoder.table = harness.geocoder.table.filter { $0.lat != 60.72 }
        let asked = { harness.geocoder.askedLatitudes.filter { abs($0 - 60.72) < 0.5 }.count }
        await harness.model.refresh()
        await waitUntil("asked once") { asked() == 1 }
        await waitUntil("Japan named") { harness.model.journeys.contains { $0.name?.title == "Japan" } }

        for _ in 0..<3 {
            harness.model.loadTrips()
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(asked(), 1, "one lookup per journey, an unanswered one included")
        let whitehorse = try XCTUnwrap(harness.model.journeys.first)
        XCTAssertNil(whitehorse.name)
        XCTAssertFalse(harness.model.awaitsName(whitehorse), "no spinner for a name that is not coming")
        XCTAssertEqual(whitehorse.headline, whitehorse.fallbackTitle, "it keeps its month")

        await harness.model.refresh()
        await waitUntil("pull-to-refresh asks again") { asked() == 2 }
    }
}

@testable import Kamome
import XCTest

/// **Hiding a found journey, and showing it again** (#167; Chiu 2026-10-03:
/// a row at the foot of the list). Its own file because the test class body
/// is held to 250 lines under SwiftLint; the harness is the class's own.
extension JourneyDiscoveryModelTests {
    func testHidingAJourneyKeepsItHiddenAcrossScans() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let whitehorse = try XCTUnwrap(harness.model.journeys.first)

        harness.model.hide(whitehorse)
        XCTAssertEqual(harness.model.journeys.count, 1)
        await harness.model.refresh()
        XCTAssertEqual(harness.model.journeys.count, 1, "hidden stays hidden")
        XCTAssertFalse(harness.model.journeys.contains { $0.id == whitehorse.id })
    }

    /// **A hidden journey can be shown again** (Chiu 2026-10-03, #167): it
    /// moves to the hidden row, stays there across scans, and comes back to
    /// the list from it — and stays back.
    func testAHiddenJourneyCanBeShownAgain() async throws {
        let harness = try makeHarness()
        await harness.model.refresh()
        let whitehorse = try XCTUnwrap(harness.model.journeys.first)
        XCTAssertTrue(harness.model.hiddenJourneys.isEmpty, "nothing hidden, no row")

        harness.model.hide(whitehorse)
        XCTAssertEqual(harness.model.hiddenJourneys.map(\.id), [whitehorse.id])
        await harness.model.refresh()
        XCTAssertEqual(harness.model.hiddenJourneys.map(\.id), [whitehorse.id], "still in the row after a scan")
        XCTAssertFalse(harness.model.journeys.contains { $0.id == whitehorse.id })

        let hidden = try XCTUnwrap(harness.model.hiddenJourneys.first)
        harness.model.unhide(hidden)
        XCTAssertTrue(harness.model.hiddenJourneys.isEmpty)
        XCTAssertEqual(harness.model.journeys.first?.id, whitehorse.id, "back where it sits by date")
        await harness.model.refresh()
        XCTAssertTrue(harness.model.journeys.contains { $0.id == whitehorse.id }, "shown again for good")
        XCTAssertTrue(harness.model.hiddenJourneys.isEmpty)

        // A journey shown again can be opened like any other.
        let shown = try XCTUnwrap(harness.model.journeys.first { $0.id == whitehorse.id })
        let tripId = await harness.model.open(shown)
        XCTAssertNotNil(tripId)
    }

    /// A hidden journey costs no lookup (§0: one per journey the person can
    /// see); shown again, it gets its one.
    func testAHiddenJourneyIsLookedUpOnlyOnceShownAgain() async throws {
        let first = try makeHarness()
        await first.model.refresh()
        // Its lookups finish first, or they write the cache after it is cleared.
        await waitUntil("the first run names both") { first.geocoder.lookups == 2 }
        let whitehorse = try XCTUnwrap(first.model.journeys.first)
        first.model.hide(whitehorse)
        // A relaunch with no place cached yet.
        first.defaults.removeObject(forKey: "kamome.journeyPlaces")

        let harness = try makeHarness(defaults: first.defaults)
        await harness.model.refresh()
        await waitUntil("the visible journey is named") { harness.model.journeys.allSatisfy { $0.name != nil } }
        XCTAssertEqual(harness.geocoder.lookups, 1, "only Japan is looked up")
        XCTAssertFalse(harness.geocoder.askedLatitudes.contains { abs($0 - 60.72) < 0.5 }, "never Whitehorse")
        XCTAssertEqual(harness.model.hiddenJourneys.map(\.id), [whitehorse.id])

        harness.model.unhide(try XCTUnwrap(harness.model.hiddenJourneys.first))
        await waitUntil("the journey shown again is named") {
            harness.model.journeys.first { $0.id == whitehorse.id }?.name?.title == "Whitehorse"
        }
        XCTAssertEqual(harness.geocoder.lookups, 2)
    }
}

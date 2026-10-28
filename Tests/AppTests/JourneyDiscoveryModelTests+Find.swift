@testable import Kamome
import XCTest

/// **「找出我的旅程」 pressed in 旅程** (#290, ADR
/// 2026-10-26-home-shows-a-newcomer-the-next-step): it asks for the library
/// as 足跡's own welcome card does, and the library is asked for and scanned
/// once, whichever of Home and 足跡's first appearance gets there first.
extension JourneyDiscoveryModelTests {
    func testPressedBeforeFootprintsWasShownTheFirstLookAsks() async throws {
        let harness = try makeHarness()
        harness.library.access = .undetermined
        harness.library.answer = .granted

        XCTAssertNil(harness.model.findJourneys(), "足跡 has not looked yet: its first look asks, not a second caller")
        XCTAssertEqual(harness.library.accessRequests, 0)
        XCTAssertTrue(harness.library.queries.isEmpty, "nothing is read before 足跡 appears")

        await harness.model.firstLook()
        XCTAssertEqual(harness.library.accessRequests, 1, "asked once")
        XCTAssertEqual(harness.library.queries.count, 1, "scanned once")
        XCTAssertEqual(harness.model.journeys.count, 2)
    }

    func testWithoutTheButtonTheFirstLookOnlyReads() async throws {
        let harness = try makeHarness()
        harness.library.access = .undetermined
        harness.library.answer = .granted

        await harness.model.firstLook()
        XCTAssertEqual(harness.library.accessRequests, 0, "opening 足跡 shows its welcome card; it does not ask")
        XCTAssertTrue(harness.library.queries.isEmpty)
        XCTAssertEqual(harness.model.phase, .ready)
    }

    func testPressedAfterFootprintsWasShownAsksNow() async throws {
        let harness = try makeHarness()
        harness.library.access = .undetermined
        await harness.model.firstLook()

        harness.library.answer = .granted
        let asking = try XCTUnwrap(harness.model.findJourneys(), "nobody has answered: it asks now")
        await asking.value
        XCTAssertEqual(harness.library.accessRequests, 1)
        XCTAssertEqual(harness.library.queries.count, 1)
        XCTAssertEqual(harness.model.journeys.count, 2)
    }

    func testPressedOnceAnsweredAsksNothingMore() async throws {
        for answered in [PhotoReadAccess.granted, .denied] {
            let harness = try makeHarness()
            harness.library.access = answered
            await harness.model.firstLook()
            let queries = harness.library.queries.count

            XCTAssertNil(harness.model.findJourneys(), "\(answered): 足跡 already shows what there is")
            XCTAssertEqual(harness.library.accessRequests, 0)
            XCTAssertEqual(harness.library.queries.count, queries, "\(answered): no second scan")
        }
    }
}

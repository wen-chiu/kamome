@testable import Kamome
import XCTest

/// **No scan and no lookup at launch** (Footprints ADR draft, Data 5, and
/// "Tests owed"). Every launch opens on 旅程 (Chiu 2026-10-07); `HomeView`
/// creates the Footprints model only when 足跡 is chosen, and the scan starts
/// on Footprints' first appearance. These pin the two halves a test can
/// reach: the launch segment, and a model that reads nothing until it is
/// asked to. Its own file: the test class body is held to 250 lines.
extension JourneyDiscoveryModelTests {
    func testEveryLaunchOpensOnJourneys() {
        XCTAssertEqual(HomeSegment.atLaunch, .journeys)
    }

    func testAFootprintsModelReadsNothingUntilItIsShown() async throws {
        let harness = try makeHarness()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(harness.library.queries.isEmpty, "the library is not read")
        XCTAssertEqual(harness.geocoder.lookups, 0, "nothing is looked up")
        XCTAssertTrue(harness.model.journeys.isEmpty)

        // Shown: the scan runs, and its lookups with it.
        await harness.model.refresh()
        XCTAssertEqual(harness.library.queries.count, 1)
    }
}

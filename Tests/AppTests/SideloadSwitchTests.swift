@testable import Kamome
import XCTest

/// **The map-region side-load is a testing switch, off in what ships**
/// (arch review 2026-09-24).
///
/// It used to be on in every configuration: Documents was open in Finder, and a
/// `.pmtiles` file dropped there overrode OpenFreeMap in the film — fixed dark,
/// OSM credit only. Now the `KAMOME_SIDELOAD_REGIONS` build setting adds the
/// file-sharing keys (YES in Debug, NO in Release) and the tile search reads the
/// same key back. The artifact half is `Scripts/release/check-archive.sh`.
final class SideloadSwitchTests: XCTestCase {
    func testTheFileSharingKeysComeOnlyFromTheSwitch() throws {
        // The plist every configuration starts from carries neither key.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
        let source = try String(contentsOf: root.appendingPathComponent("App/Info.plist"), encoding: .utf8)
        XCTAssertTrue(source.contains("CFBundleDisplayName"), "precondition: App/Info.plist was read")
        XCTAssertFalse(source.contains("UIFileSharingEnabled"),
                       "App/Info.plist opens Documents in Finder for every configuration")
        XCTAssertFalse(source.contains("LSSupportsOpeningDocumentsInPlace"),
                       "App/Info.plist opens Documents in the Files app for every configuration")

        // The running half: this test is hosted by the built app.
        #if DEBUG
        XCTAssertTrue(RecapMapTiles.sideloadEnabled, "the Debug switch phase did not add UIFileSharingEnabled")
        #else
        XCTAssertFalse(RecapMapTiles.sideloadEnabled, "a non-Debug build opens the side-load folder")
        #endif
    }

    func testSwitchedOffTheExportSearchesNoContainerFolder() throws {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let inContainer: (URL) -> Bool = {
            $0.path.hasPrefix(documents.path) || $0.path.hasPrefix(support.path)
        }

        let off = RecapMapTiles.searchDirectories(bundle: .main, sideload: false)
        XCTAssertFalse(off.contains(where: inContainer), "switched off, a side-loaded region can still reach the film")

        // Precondition that the test above can fail: switched on, both are searched.
        let on = RecapMapTiles.searchDirectories(bundle: .main, sideload: true)
        XCTAssertTrue(on.contains(where: inContainer))
    }
}

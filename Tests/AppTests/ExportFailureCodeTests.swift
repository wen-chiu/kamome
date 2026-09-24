@testable import Kamome
import XCTest

/// **A failed export names its cause without naming a place**
/// (arch review 2026-09-24, P1-6). The screen used to show the raw error, and a
/// MapLibre tile failure carries its tile URL — z/x/y is a location (§0).
final class ExportFailureCodeTests: XCTestCase {
    func testTheScreenGetsDomainAndCodeButNeverTheTileURL() {
        let failure = NSError(
            domain: "MLNErrorDomain", code: 6,
            userInfo: [
                NSURLErrorFailingURLStringErrorKey: "https://tiles.openfreemap.org/planet/14/14056/6488.pbf",
                NSLocalizedDescriptionKey: "Tile 14/14056/6488 failed to load"
            ]
        )

        let shown = RecapExportJob.failureCode(failure)

        XCTAssertEqual(shown, "MLNErrorDomain · 6")
        XCTAssertFalse(shown.contains("14056"), "a tile coordinate reached the screen")
    }
}

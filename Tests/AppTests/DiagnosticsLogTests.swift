@testable import Kamome
import KamomeConfig
import OSLog
import XCTest

/// **The diagnostics export carries Kamome's own lines and nothing else**
/// (ADR 2026-09-24 (d)). It is what a TestFlight tester hands back after a D1–D5
/// run, so it must hold the measurements and must not hold anything a
/// neighbouring subsystem logged.
final class DiagnosticsLogTests: XCTestCase {
    func testTheExportHoldsKamomeLinesFromThisLaunchOnly() throws {
        let marker = "diagnostics-probe-\(UUID().uuidString)"
        KamomeLog.recap.notice("\(marker, privacy: .public) kamome")
        Logger(subsystem: "com.example.other", category: "x").notice("\(marker, privacy: .public) other")

        let url = try XCTUnwrap(DiagnosticsLog.export())
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("\(marker) kamome"), "a Kamome line from this launch is missing")
        XCTAssertFalse(text.contains("\(marker) other"), "another subsystem's line reached the file")
        XCTAssertTrue(text.hasPrefix("Kamome diagnostics"))
    }

    func testEachLineNamesTimeCategoryAndLevel() {
        let text = DiagnosticsLog.render(header: ["H"], lines: [
            DiagnosticsLog.Line(
                date: Date(timeIntervalSince1970: 0), category: "recap", level: "ERROR", message: "export failed"
            )
        ])
        XCTAssertTrue(text.contains("[recap] ERROR export failed"))
        XCTAssertTrue(text.contains("1 lines"))
    }
}

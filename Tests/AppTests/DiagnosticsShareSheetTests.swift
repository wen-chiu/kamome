import XCTest

/// **The diagnostics share sheet hangs on About's list, never inside a row**
/// (#189). Presented from `DiagnosticsSection` it was created and torn down
/// within a second on iOS 26, and About went with it — so the file the device
/// runbook is read from could not be shared.
///
/// No unit test can see a sheet stay up; that was checked on the simulator.
/// This holds the cause: it reads the two source files, the way
/// `LocalizationCoverageTests` reads the UI for its keys.
final class DiagnosticsShareSheetTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testTheRowPresentsNothingItself() throws {
        let file = try source("UI/About/DiagnosticsSection.swift")
        let start = try XCTUnwrap(file.range(of: "struct DiagnosticsSection: View {"))
        let end = try XCTUnwrap(file.range(of: "\n}\n", range: start.upperBound..<file.endIndex))
        let row = file[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(row.contains("about_export_diagnostics"), "this is not the row's body any more")
        for presentation in [".sheet(", ".fullScreenCover(", ".popover("] {
            XCTAssertFalse(
                row.contains(presentation),
                "\(presentation) inside the diagnostics row: a sheet in a List row is taken down as it appears (#189)"
            )
        }
    }

    func testAboutPresentsTheShareSheetOnItsList() throws {
        let about = try source("UI/About/AboutView.swift")
        XCTAssertTrue(about.contains("DiagnosticsSection(file: $diagnosticsFile)"))
        XCTAssertTrue(
            about.contains(".diagnosticsShareSheet($diagnosticsFile)"),
            "nothing presents the exported file: the row only says which file to share"
        )
    }
}

import CoreGraphics
@testable import Kamome
import KamomePersistence
import XCTest

/// **Trip Detail's 「刪除地點」 points at the stop that was swiped** (#326, Chiu
/// 2026-10-29), the way Home's 「刪除旅程」 does (ADR
/// 2026-10-28-home-asks-about-a-trip-at-its-row). It hung on the whole list,
/// so on iOS 26 its arrow sat between the map and the first stop.
///
/// Where iOS draws the arrow was checked on the simulator: the arrow at the
/// swiped row, the row slid back with its name, Cancel keeping the stop and
/// 刪除地點 deleting it. These hold what that rests on.
@MainActor
final class StopDeletionPromptTests: XCTestCase {
    private func stop(_ id: String) -> StopRecord {
        StopRecord(id: id, tripId: "trip", lat: 0, lon: 0, arrivedAt: 0)
    }

    private let upper = CGRect(x: 0, y: 480, width: 402, height: 66)
    private let lower = CGRect(x: 0, y: 546, width: 402, height: 66)

    func testTheQuestionPointsAtTheSwipedStopNotAnother() {
        let prompt = RowDeletionPrompt<StopRecord>()
        prompt.row("a", isAt: upper)
        prompt.row("b", isAt: lower)

        prompt.ask(about: stop("b"))
        XCTAssertEqual(prompt.item?.id, "b")
        XCTAssertEqual(prompt.anchor, lower, "the arrow goes to b's row, not a's and not the whole list")
    }

    func testAnUnreportedStopIsStillAsked() {
        let prompt = RowDeletionPrompt<StopRecord>()
        prompt.ask(about: stop("a"))
        XCTAssertEqual(prompt.item?.id, "a", "deleting a stop always asks first (ADR 2026-10-02-deleting-a-stop-asks-first)")
        XCTAssertNil(prompt.anchor)
    }

    // MARK: - The source, the way `TripDeletionPromptTests` reads Home's

    /// The stop row's code, its `//` comments dropped.
    private func stopRow() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(
            contentsOf: repoRoot.appendingPathComponent("UI/TripDetail/TripDetailView.swift"), encoding: .utf8
        )
        let start = try XCTUnwrap(file.range(of: "ForEach(model.visibleStops, id: \\.id) { stop in"))
        let end = try XCTUnwrap(file.range(of: "RoutePhotosRow(", range: start.upperBound..<file.endIndex))
        let row = file[start.lowerBound..<end.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(row.contains("stopDeletion.ask(about: stop)"), "this is not the stop row any more")
        return row
    }

    /// A presentation inside a `List` row is taken down as it appears (#189).
    func testTheStopRowPresentsNothingItself() throws {
        let row = try stopRow()
        for presentation in [".confirmationDialog(", ".alert(", ".sheet(", ".fullScreenCover(", ".popover("] {
            XCTAssertFalse(row.contains(presentation), "\(presentation) inside the stop row (#189)")
        }
    }

    /// The row reports where it is, or the dialog has nowhere to point.
    func testTheStopRowReportsItsPlace() throws {
        XCTAssertTrue(try stopRow().contains("stopDeletion.row(stop.id, isAt:"))
    }

    /// `role: .destructive` animates the row out and back while the question
    /// is asked (Home, VERIFIED 2026-10-28). Tinted red, the row slides back
    /// and shows its name under the dialog (#326, VERIFIED 2026-10-29).
    func testTheSwipeButtonDoesNotAnimateItsRowAway() throws {
        let row = try stopRow()
        XCTAssertFalse(row.contains("role: .destructive"), "the destructive role moves the row the dialog points at")
        XCTAssertTrue(row.contains(".tint(.red)"), "the swipe button keeps its red")
    }
}

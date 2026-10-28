import CoreGraphics
@testable import Kamome
import KamomePersistence
import XCTest

/// **Home's 「刪除旅程」 points at the row that was swiped** (#295 item 8, Chiu
/// 2026-10-28; ADR 2026-10-28-home-asks-about-a-trip-at-its-row). On iOS 26 the
/// dialog is a popover, and hung on the list its arrow pointed at the import
/// button.
///
/// No unit test can see where iOS draws the arrow; that was checked on the
/// simulator, and the screenshots are in the PR. These hold what it rests on:
/// the question is anchored at the asked-about trip's own row and follows that
/// row if it moves; nothing is presented from inside a row (#189); and the
/// swipe button does not animate its row away while the question is asked.
@MainActor
final class TripDeletionPromptTests: XCTestCase {
    private func trip(_ id: String) -> TripRecord {
        TripRecord(id: id, title: id, startedAt: 0, endedAt: 1_000, status: "completed")
    }

    private let upper = CGRect(x: 0, y: 100, width: 402, height: 96)
    private let lower = CGRect(x: 0, y: 196, width: 402, height: 96)

    func testTheQuestionPointsAtTheSwipedRowNotAnother() {
        let prompt = TripDeletionPrompt()
        prompt.row("a", isAt: upper)
        prompt.row("b", isAt: lower)

        prompt.ask(about: trip("b"))
        XCTAssertEqual(prompt.trip?.id, "b")
        XCTAssertEqual(prompt.anchor, lower, "the arrow goes to b's row, not a's and not the whole list")
    }

    /// The list can move under the dialog. With the destructive role it jumped
    /// about a row at its foot (2026-10-28), so the arrow has to go with it.
    func testTheAnchorFollowsTheAskedAboutRowAndNoOther() {
        let prompt = TripDeletionPrompt()
        prompt.row("a", isAt: upper)
        prompt.row("b", isAt: lower)
        prompt.ask(about: trip("b"))

        let moved = lower.offsetBy(dx: 0, dy: -90)
        prompt.row("b", isAt: moved)
        XCTAssertEqual(prompt.anchor, moved, "b moved while asked about: the arrow follows")

        prompt.row("a", isAt: upper.offsetBy(dx: 0, dy: -90))
        XCTAssertEqual(prompt.anchor, moved, "another row moving does not take the arrow")
    }

    func testRowsMovingWithNoQuestionSetNoAnchor() {
        let prompt = TripDeletionPrompt()
        prompt.row("a", isAt: upper)
        XCTAssertNil(prompt.trip)
        XCTAssertNil(prompt.anchor)
    }

    /// A row that never reported falls back to the whole list, as before the
    /// fix, and the question is still asked: deleting always asks first (ADR
    /// 2026-10-02-deleting-a-stop-asks-first).
    func testAnUnreportedRowIsStillAsked() {
        let prompt = TripDeletionPrompt()
        prompt.ask(about: trip("a"))
        XCTAssertEqual(prompt.trip?.id, "a")
        XCTAssertNil(prompt.anchor)
    }

    // MARK: - The source, the way `DiagnosticsShareSheetTests` reads it (#189)

    /// The trip row's code, its `//` comments dropped: the comment that says
    /// why the role is gone names the role.
    private func homeTripRow() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: repoRoot.appendingPathComponent("UI/Home/HomeView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(file.range(of: "ForEach(session.trips) { trip in"))
        let end = try XCTUnwrap(file.range(of: "HomeNextStep.isOffered", range: start.upperBound..<file.endIndex))
        let row = file[start.lowerBound..<end.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(row.contains("deletion.ask(about: trip)"), "this is not the trip row any more")
        return row
    }

    /// Hung on the row, the dialog was created and taken down within 1.1 s and
    /// nothing could be deleted (VERIFIED 2026-10-28, simulator, 2 of 2).
    func testTheTripRowPresentsNothingItself() throws {
        let row = try homeTripRow()
        for presentation in [".confirmationDialog(", ".alert(", ".sheet(", ".fullScreenCover(", ".popover("] {
            XCTAssertFalse(
                row.contains(presentation),
                "\(presentation) inside the trip row: a presentation in a List row is taken down as it appears (#189)"
            )
        }
    }

    /// `role: .destructive` animates the row out and back while the question
    /// is asked; at the list's foot that scrolled the row under the import
    /// button (VERIFIED 2026-10-28). The button is tinted red instead.
    func testTheSwipeButtonDoesNotAnimateItsRowAway() throws {
        let row = try homeTripRow()
        XCTAssertFalse(row.contains("role: .destructive"), "the destructive role moves the row the dialog points at")
        XCTAssertTrue(row.contains(".tint(.red)"), "the swipe button keeps its red")
    }
}

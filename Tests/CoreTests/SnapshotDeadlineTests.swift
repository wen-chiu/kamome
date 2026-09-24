@testable import KamomeExportEngine
import XCTest

/// The race behind `export.pipeline.snapshot_timeout_s` (arch review
/// 2026-09-24, P1-10): whichever of the work and the deadline finishes first
/// decides, exactly once.
final class SnapshotDeadlineTests: XCTestCase {
    func testWorkThatAnswersInTimeIsReturned() async throws {
        let value = try await SnapshotDeadline.run(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testWorkThatNeverAnswersTimesOut() async throws {
        let started = ContinuousClock.now
        do {
            _ = try await SnapshotDeadline.run(seconds: 0.2) {
                try await withCheckedThrowingContinuation { (_: CheckedContinuation<Int, Error>) in }
            }
            XCTFail("a callback that never fires must not hold the caller")
        } catch let timeout as SnapshotTimeout {
            XCTAssertEqual(timeout.seconds, 0.2)
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
        }
    }

    func testTheWorksOwnErrorIsNotReportedAsATimeout() async throws {
        struct Refused: Error {}
        do {
            _ = try await SnapshotDeadline.run(seconds: 5) { () async throws -> Int in throw Refused() }
            XCTFail("expected the work's error")
        } catch is Refused {
            // The substrate's own failure (a tile host down) keeps its identity.
        }
    }
}

@testable import Kamome
import XCTest

/// **Cancel is read while the export finds roads** (#277).
///
/// The export used to await routing — bounded by `matching.trip_budget_s`,
/// 120 s — before it looked at Cancel again, so a Cancel pressed in "finding
/// roads" landed up to two minutes later. `RecapExportJob.waiting` is the wait
/// it uses now: the answer if it comes first, nil as soon as Cancel does.
@MainActor
final class RecapExportCancelWaitTests: XCTestCase {
    func testCancelEndsTheWaitWithoutWaitingForTheWork() async {
        let cancelled = SharedFlag()
        let started = ContinuousClock.now
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            cancelled.set()
        }
        let answer = await RecapExportJob.waiting(
            for: {
                try? await Task.sleep(for: .seconds(30))
                return 1
            },
            unless: { !cancelled.isSet }
        )
        XCTAssertNil(answer, "a cancelled wait has no answer")
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "the wait ended with the Cancel, not the work")
    }

    func testAnAnswerThatComesFirstIsReturned() async {
        let answer = await RecapExportJob.waiting(for: { 42 }, unless: { true })
        XCTAssertEqual(answer, 42)
    }

    func testAnAlreadyCancelledExportDoesNotWaitAtAll() async {
        let started = ContinuousClock.now
        let answer = await RecapExportJob.waiting(
            for: {
                try? await Task.sleep(for: .seconds(30))
                return 1
            },
            unless: { false }
        )
        XCTAssertNil(answer)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }
}

@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import UIKit
import XCTest

/// **Phase 4 closeout step 2: the export outlives the screen** (Chiu 2026-09-10).
///
/// Four rules, each of which used to be held by something that is now gone —
/// `interactiveDismissDisabled`, a `cancel()` in the Done button, and a model
/// that owned the render and died with the sheet. They are tests rather than
/// comments because every one of them fails silently: a second writer crashes
/// on a phone and never in CI, and a leaked lifecycle guard is invisible until
/// the battery is gone.
@MainActor
final class RecapExportCoordinatorTests: XCTestCase {
    // MARK: - Harness

    private func request(_ tripId: String) -> RecapExportRequest {
        RecapExportRequest(tripId: tripId, photosEnabled: true, format: .mp4, appearance: .dark)
    }

    private func film(_ tripId: String) -> FilmRecord {
        FilmRecord(
            id: UUID().uuidString, tripId: tripId, relativePath: "Films/test.mp4",
            format: "mp4", createdAt: 0, durationS: 60, renderSeconds: 65.6,
            appearance: "dark", recapMode: "highlight", fileBytes: 33_300_000
        )
    }

    private func finished(_ tripId: String) -> RecapExportOutcome {
        .finished(film: film(tripId), fileURL: URL(fileURLWithPath: "/tmp/test.mp4"))
    }

    /// Spins the main actor until the condition holds. The coordinator starts
    /// its job in a `Task`, so nothing has entered `run` on the line after
    /// `start` returns.
    private func waitUntil(
        _ description: String, _ condition: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "timed out waiting for: \(description)", file: file, line: line)
    }

    override func setUp() {
        super.setUp()
        SpyExportJob.resetCounters()
    }

    // MARK: - The export outlives the screen

    /// **The whole point of step 2.** The sheet's `RecapModel` is destroyed
    /// mid-render — which is exactly what dismissing the sheet does — and the
    /// export finishes anyway, writes its record, and is there when the screen
    /// comes back.
    func testAnExportSurvivesTheSheetBeingDismissedAndStillProducesItsFilmRecord() async throws {
        let coordinator = RecapExportCoordinator()
        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let job = SpyExportJob()

        // The sheet is open, and the render is running.
        var sheetModel: RecapModel? = RecapModel(
            tripId: "trip-a", config: config, repository: repository, coordinator: coordinator
        )
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }
        job.report(progress: 0.4)
        XCTAssertEqual(sheetModel?.phase, .rendering(progress: 0.4))

        // The sheet is dismissed. Under the old design this deallocated the
        // owner of the render, and Done cancelled it on the way out besides.
        weak var deallocated = sheetModel
        sheetModel = nil
        XCTAssertNil(deallocated, "the sheet's model must really be gone for this test to mean anything")

        XCTAssertTrue(coordinator.isRendering(tripId: "trip-a"), "the render must not have noticed")
        XCTAssertFalse(job.isCancelled, "dismissing the sheet must not cancel")

        job.complete(finished("trip-a"))
        await waitUntil("the export to finish") { !coordinator.isRendering(tripId: "trip-a") }

        // The screen comes back — a brand new model, as the sheet builds one.
        let reopened = RecapModel(
            tripId: "trip-a", config: config, repository: repository, coordinator: coordinator
        )
        guard case let .finished(record, _) = reopened.phase else {
            return XCTFail("a film that landed while nobody was looking must still be there: \(reopened.phase)")
        }
        XCTAssertEqual(record.tripId, "trip-a")
    }

    /// Reopening a trip whose export is still running shows the render, not an
    /// idle Export button — and shows the settings the film in flight is using
    /// rather than the fresh model's defaults.
    func testReopeningATripMidRenderShowsTheRunningExport() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        let running = RecapExportRequest(
            tripId: "trip-a", photosEnabled: false, format: .gif, appearance: .light
        )
        coordinator.start(request: running, job: job)
        await waitUntil("the job to start") { job.hasStarted }
        job.report(progress: 0.25)

        let reopened = RecapModel(
            tripId: "trip-a", config: AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            coordinator: coordinator
        )
        XCTAssertTrue(reopened.isRendering)
        XCTAssertEqual(reopened.phase, .rendering(progress: 0.25))
        XCTAssertFalse(reopened.photosEnabled, "the screen must show the running film's settings")
        XCTAssertEqual(reopened.format, .gif)
    }

    // MARK: - One export at a time

    /// **Join or refuse, never start a second.** A back button means the user
    /// can leave a running export, open another trip and tap Export there; two
    /// `AVAssetWriter`s on a phone is a crash rather than a slowdown.
    func testASecondExportRequestNeverOpensASecondWriter() async throws {
        let coordinator = RecapExportCoordinator()
        let first = SpyExportJob()
        XCTAssertEqual(coordinator.start(request: request("trip-a"), job: first), .started)
        await waitUntil("the first job to start") { first.hasStarted }

        // Same trip: joined. A second job object is handed over and must never
        // be run — that is the difference between joining and starting.
        let sameTrip = SpyExportJob()
        XCTAssertEqual(coordinator.start(request: request("trip-a"), job: sameTrip), .joined)

        // Another trip: refused, and told which trip is busy so the screen can
        // say so rather than looking like a dead button.
        let otherTrip = SpyExportJob()
        XCTAssertEqual(
            coordinator.start(request: request("trip-b"), job: otherTrip),
            .refused(busyTripId: "trip-a")
        )

        await waitUntil("any second job to have had its chance to start") { true }
        XCTAssertFalse(sameTrip.hasStarted, "a joined request must reuse the run, not start one")
        XCTAssertFalse(otherTrip.hasStarted, "a refused request must not render")
        XCTAssertEqual(SpyExportJob.runs, 1)
        XCTAssertEqual(SpyExportJob.peak, 1, "two concurrent runs is two AVAssetWriters")
        XCTAssertEqual(coordinator.running?.tripId, "trip-a")

        first.complete(finished("trip-a"))
        await waitUntil("the first export to finish") { coordinator.running == nil }
        XCTAssertEqual(SpyExportJob.peak, 1)
    }

    /// The refusal reaches the screen. `RecapModel` is what the sheet asks, so
    /// a refusal it swallowed would be indistinguishable from a dead button.
    func testTheScreenIsToldWhichTripIsBusy() async throws {
        let coordinator = RecapExportCoordinator()
        let running = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: running)
        await waitUntil("the first job to start") { running.hasStarted }

        let otherTrip = RecapModel(
            tripId: "trip-b", config: AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            coordinator: coordinator
        )
        otherTrip.startExport(appearance: .dark)
        XCTAssertEqual(otherTrip.busyTripId, "trip-a")
        XCTAssertFalse(otherTrip.isRendering)
        XCTAssertEqual(SpyExportJob.runs, 1)
    }

    // MARK: - Cancel

    /// Cancel is still an explicit user action and still cancels. Dismissing no
    /// longer does — that is the pairing this whole step turns on.
    func testCancelStillCancelsAndDismissingDoesNot() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        let model = RecapModel(
            tripId: "trip-a", config: AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            coordinator: coordinator
        )
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }

        XCTAssertFalse(job.isCancelled)
        model.cancel()
        XCTAssertTrue(job.isCancelled, "the render loop must see the flag at its next frame")

        job.complete(.cancelled)
        await waitUntil("the export to end") { coordinator.running == nil }
        // A cancelled export leaves the trip idle rather than showing a failure:
        // the user asked for it, so it is not an error to report back to them.
        XCTAssertEqual(model.phase, .idle)
    }

    /// A stale screen must not cancel a run that has moved on to another trip.
    func testCancellingFromTheWrongTripDoesNothing() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }

        coordinator.cancel(tripId: "trip-b")
        XCTAssertFalse(job.isCancelled)
        coordinator.cancel(tripId: "trip-a")
        XCTAssertTrue(job.isCancelled)
    }

    // MARK: - What an outcome that outlives its screen has to keep straight

    /// Deleting a film from the trip screen must clear the export sheet's memory
    /// of it. The outcome now outlives the sheet, so without this the sheet
    /// reopens playing a file that is gone.
    func testDeletingAFilmClearsTheOutcomeStillHoldingIt() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }
        let record = film("trip-a")
        job.complete(.finished(film: record, fileURL: URL(fileURLWithPath: "/tmp/test.mp4")))
        await waitUntil("the export to finish") { coordinator.running == nil }
        XCTAssertNotNil(coordinator.outcome(tripId: "trip-a"))

        // A different film of the same trip must not clear it.
        coordinator.forget(film: film("trip-a"))
        XCTAssertNotNil(coordinator.outcome(tripId: "trip-a"), "only the deleted film is forgotten")

        coordinator.forget(film: record)
        XCTAssertNil(coordinator.outcome(tripId: "trip-a"))
    }

    /// A cancelled run's progress hops back to the main actor as fire-and-forget
    /// `Task`s, so some can still be in flight when the next export starts.
    /// Landing them in the new run would report another film's percentage.
    func testAStaleRunCannotWriteProgressIntoTheNextOne() async throws {
        let coordinator = RecapExportCoordinator()
        let stale = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: stale)
        await waitUntil("the first job to start") { stale.hasStarted }
        stale.report(progress: 0.9)
        coordinator.cancel(tripId: "trip-a")
        stale.complete(.cancelled)
        await waitUntil("the first export to end") { coordinator.running == nil }

        let fresh = SpyExportJob()
        coordinator.start(request: request("trip-b"), job: fresh)
        await waitUntil("the second job to start") { fresh.hasStarted }
        fresh.report(progress: 0.1)

        // The cancelled run, still holding its channel, tries to report again.
        stale.report(progress: 0.9)
        XCTAssertEqual(coordinator.running?.tripId, "trip-b")
        XCTAssertEqual(coordinator.running?.fraction, 0.1, "a finished run must not write into the live one")
    }

    // MARK: - The lifecycle guard, on all four exits

    /// **Finish, cancel, failure, expiry — the screen is released on every one.**
    /// A screen pinned awake is a worse bug than the one the guard fixes, and it
    /// is invisible until the battery is gone.
    func testTheLifecycleGuardIsReleasedOnEveryExitPath() async throws {
        for exit in ExitPath.allCases {
            let platform = FakePlatform()
            let coordinator = RecapExportCoordinator(
                lifecycle: ExportLifecycleGuard(platform: platform.platform)
            )
            let job = SpyExportJob()
            coordinator.start(request: request("trip-a"), job: job)
            await waitUntil("the job to start (\(exit))") { job.hasStarted }

            XCTAssertEqual(platform.heldAssertions, 1, "[\(exit)] the render must hold one assertion")
            XCTAssertTrue(platform.idleTimerDisabled, "[\(exit)] the screen must be pinned awake")

            switch exit {
            case .finished:
                job.complete(finished("trip-a"))
            case .cancelled:
                coordinator.cancel(tripId: "trip-a")
                job.complete(.cancelled)
            case .failed:
                job.complete(.failed(message: "boom"))
            case .expired:
                // iOS reclaiming the assertion. The guard lets go immediately —
                // an expiry handler that does not end its own task is killed —
                // and the export stops at its next frame boundary.
                platform.expiry?()
                XCTAssertTrue(job.isCancelled, "[expired] the render must be told to stop")
                XCTAssertEqual(platform.heldAssertions, 0, "[expired] released before the run unwinds")
                job.complete(.cancelled)
            }

            await waitUntil("the export to end (\(exit))") { coordinator.running == nil }
            XCTAssertEqual(platform.heldAssertions, 0, "[\(exit)] background assertion leaked")
            XCTAssertFalse(platform.idleTimerDisabled, "[\(exit)] the screen is still pinned awake")
            XCTAssertFalse(coordinator.isHoldingLifecycle, "[\(exit)] the guard still thinks it holds one")
        }
    }

    private enum ExitPath: CaseIterable, CustomStringConvertible {
        case finished, cancelled, failed, expired

        var description: String {
            switch self {
            case .finished: return "finished"
            case .cancelled: return "cancelled"
            case .failed: return "failed"
            case .expired: return "expired"
            }
        }
    }
}

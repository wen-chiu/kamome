@testable import Kamome
import KamomePersistence
import XCTest

/// **An export that leaving Kamome ended says so** (#260, device run
/// 2026-10-09). On the phone, an app switch cancelled the export as though the
/// user had pressed Cancel and the screen went back to ready with no word; a
/// locked screen failed it as `KamomeExportEngine.SnapshotTimeout · 1`.
///
/// Driven through the real coordinator and lifecycle guard, with UIKit's
/// background notification and assertion expiry fired by `FakePlatform`.
@MainActor
final class RecapExportLeftAppTests: XCTestCase {
    private let leftAppMessage = String(localized: "recap_failed_left_app")

    private func request() -> RecapExportRequest {
        RecapExportRequest(tripId: "trip-a", photosEnabled: true, appearance: .dark)
    }

    private func waitUntil(
        _ description: String, _ condition: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "timed out waiting for: \(description)", file: file, line: line)
    }

    /// One export, started and parked: everything a test drives.
    private struct Run {
        let coordinator: RecapExportCoordinator
        let job: SpyExportJob
        let platform: FakePlatform
    }

    private func started() async -> Run {
        let platform = FakePlatform()
        let coordinator = RecapExportCoordinator(lifecycle: ExportLifecycleGuard(platform: platform.platform))
        let job = SpyExportJob()
        coordinator.start(request: request(), job: job)
        await waitUntil("the job to start") { job.hasStarted }
        return Run(coordinator: coordinator, job: job, platform: platform)
    }

    private func ended(_ coordinator: RecapExportCoordinator) async -> RecapExportOutcome? {
        await waitUntil("the export to end") { coordinator.running == nil }
        return coordinator.outcome(tripId: "trip-a")
    }

    /// An app switch: iOS takes the background time back and the render stops.
    func testAnExpiredAssertionFailsWithTheReasonInsteadOfCancellingSilently() async {
        let run = await started()
        let (coordinator, job, platform) = (run.coordinator, run.job, run.platform)

        platform.enterBackground()
        platform.expiry?()
        job.complete(.cancelled)

        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, .failed(message: leftAppMessage))
        XCTAssertNotEqual(leftAppMessage, "recap_failed_left_app", "the catalogue must carry the sentence")
    }

    /// A locked screen: the map cannot draw, and a snapshot times out.
    func testAFailureAfterLeavingTheAppSaysWhyAndNotTheErrorCode() async {
        let run = await started()
        let (coordinator, job, platform) = (run.coordinator, run.job, run.platform)

        platform.enterBackground()
        job.complete(.failed(message: "KamomeExportEngine.SnapshotTimeout · 1"))

        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, .failed(message: leftAppMessage))
    }

    func testTheUsersOwnCancelStaysACancel() async {
        let run = await started()
        let (coordinator, job) = (run.coordinator, run.job)

        coordinator.cancel(tripId: "trip-a")
        job.complete(.cancelled)

        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, .cancelled)
    }

    /// Away for a moment and back before iOS took anything: the user's Cancel
    /// afterwards is still theirs.
    func testACancelAfterABriefSwitchIsStillTheUsers() async {
        let run = await started()
        let (coordinator, job, platform) = (run.coordinator, run.job, run.platform)

        platform.enterBackground()
        coordinator.cancel(tripId: "trip-a")
        job.complete(.cancelled)

        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, .cancelled)
    }

    func testAFailureThatNeverLeftTheAppKeepsItsOwnMessage() async {
        let run = await started()
        let (coordinator, job) = (run.coordinator, run.job)

        job.complete(.failed(message: "boom"))

        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, .failed(message: "boom"))
    }

    func testAFilmThatFinishedAfterASwitchIsTheFilm() async {
        let run = await started()
        let (coordinator, job, platform) = (run.coordinator, run.job, run.platform)
        let film = FilmRecord(
            id: "film-1", tripId: "trip-a", relativePath: "Films/test.mp4", format: "mp4", createdAt: 0,
            durationS: 60, renderSeconds: 65.6, appearance: "dark", recapMode: "highlight", fileBytes: 1
        )
        let finished = RecapExportOutcome.finished(film: film, fileURL: URL(fileURLWithPath: "/tmp/test.mp4"))

        platform.enterBackground()
        job.complete(finished)

        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, finished)
    }

    /// The observer lives exactly as long as the render, and a run starts clean:
    /// one export's trip to the background must not fail the next one.
    func testTheBackgroundObserverEndsWithTheRunAndTheNextRunStartsClean() async {
        let run = await started()
        let (coordinator, job, platform) = (run.coordinator, run.job, run.platform)
        XCTAssertEqual(platform.backgroundObservers.count, 1)

        platform.enterBackground()
        job.complete(.failed(message: "boom"))
        _ = await ended(coordinator)
        XCTAssertEqual(platform.backgroundObservers.count, 0, "observer leaked past the run")

        let next = SpyExportJob()
        coordinator.start(request: request(), job: next)
        await waitUntil("the next job to start") { next.hasStarted }
        XCTAssertEqual(coordinator.leftApp, .init())
        next.complete(.failed(message: "boom"))
        let outcome = await ended(coordinator)
        XCTAssertEqual(outcome, .failed(message: "boom"))
    }
}

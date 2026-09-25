@testable import Kamome
import KamomeConfig
import KamomePersistence
import XCTest

/// **Photo analysis steps aside while a film renders** (arch review 2026-09-26,
/// round 2 point 5). Vision at background priority was only INFERRED not to
/// slow an export; not running beside one needs no measurement.
@MainActor
final class PhotoAnalysisYieldTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }

    private func startedExport() async -> (RecapExportCoordinator, SpyExportJob) {
        let exports = RecapExportCoordinator()
        let job = SpyExportJob()
        exports.start(
            request: RecapExportRequest(tripId: "rendering", photosEnabled: true, format: .mp4, appearance: .dark),
            job: job
        )
        await waitUntil { job.hasStarted }
        return (exports, job)
    }

    func testAnalysisAskedForDuringAFilmWaitsAndResumesWhenItEnds() async throws {
        let (exports, job) = await startedExport()
        let analysis = PhotoAnalysisCoordinator(exports: exports)
        let repository = TripRepository(database: try AppDatabase.inMemory())

        analysis.start(tripId: "trip", repository: repository, config: AppConfig.loadOrDie().photoAnalysis)
        XCTAssertTrue(analysis.isDeferred("trip"), "analysis started beside a rendering film")
        XCTAssertFalse(analysis.isRunning("trip"))

        job.complete(.cancelled)
        await waitUntil { exports.running == nil }
        XCTAssertFalse(analysis.isDeferred("trip"), "the film ended and the analysis was never picked up again")
        XCTAssertFalse(exports.rendering.isSet)
    }

    func testADeletedTripIsNotResumed() async throws {
        let (exports, job) = await startedExport()
        let analysis = PhotoAnalysisCoordinator(exports: exports)
        let repository = TripRepository(database: try AppDatabase.inMemory())
        analysis.start(tripId: "trip", repository: repository, config: AppConfig.loadOrDie().photoAnalysis)

        analysis.cancel(tripId: "trip")

        XCTAssertFalse(analysis.isDeferred("trip"), "a cancelled trip must not come back when the film ends")
        job.complete(.cancelled)
        await waitUntil { exports.running == nil }
    }
}

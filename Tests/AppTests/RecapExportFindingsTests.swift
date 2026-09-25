@testable import Kamome
import KamomeConfig
import KamomePersistence
import XCTest

/// What the finished-film screen still knows after the run that made it has
/// ended, and where "Export again" lands. Split from
/// `RecapExportCoordinatorTests`, which holds the single-flight and lifecycle
/// rules; the harness is the same `SpyExportJob`.
@MainActor
final class RecapExportFindingsTests: XCTestCase {
    private func request(_ tripId: String) -> RecapExportRequest {
        RecapExportRequest(tripId: tripId, photosEnabled: true, format: .mp4, appearance: .dark)
    }

    private func finished(_ tripId: String) -> RecapExportOutcome {
        let film = FilmRecord(
            id: UUID().uuidString, tripId: tripId, relativePath: "Films/test.mp4",
            format: "mp4", createdAt: 0, durationS: 60, renderSeconds: 65.6,
            appearance: "dark", recapMode: "highlight", fileBytes: 33_300_000
        )
        return .finished(film: film, fileURL: URL(fileURLWithPath: "/tmp/test.mp4"))
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

    override func setUp() {
        super.setUp()
        SpyExportJob.resetCounters()
    }

    /// **What a run found outlives the run** (2026-09-25). The shortfall and
    /// the routing report used to live only in `Running`, so the finished film —
    /// the screen someone who left comes back to — had blank cards and no
    /// reason. They are kept with a finished outcome and go when it goes.
    func testTheFinishedFilmStillSaysWhyItsCardsAreBlank() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }
        var routing = RouteMatchReport()
        routing.attempted = 4
        routing.reconstructed = 3
        job.report(routing: routing)
        job.report(shortfall: PhotoLibraryPhotoResolver.WarmSummary(requested: 3, resolved: 0, inCloud: 3))
        job.complete(finished("trip-a"))
        await waitUntil("the export to finish") { coordinator.running == nil }

        let reopened = RecapModel(
            tripId: "trip-a", config: AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            coordinator: coordinator
        )
        XCTAssertEqual(reopened.photoShortfall?.missing, 3, "the finished film must still say its cards are blank")
        XCTAssertEqual(reopened.routing, routing)

        reopened.exportAgain()
        XCTAssertNil(reopened.photoShortfall, "a finding belongs to its film, not to the next one")
        XCTAssertNil(reopened.routing)
    }

    /// A cancelled or failed run has no film to explain, so it keeps nothing.
    func testACancelledRunLeavesNoFindingsBehind() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }
        job.report(shortfall: PhotoLibraryPhotoResolver.WarmSummary(requested: 3, resolved: 0, inCloud: 3))
        job.complete(.cancelled)
        await waitUntil("the export to end") { coordinator.running == nil }
        XCTAssertNil(coordinator.findings(tripId: "trip-a"))
    }

    /// **Export again goes back to the form; it does not render** (2026-09-25).
    /// It used to start the next film at once, so the only way to change the
    /// vehicle or the photos between two films was to delete the first.
    func testExportAgainReturnsToTheFormWithoutStartingARender() async throws {
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request("trip-a"), job: job)
        await waitUntil("the job to start") { job.hasStarted }
        job.complete(finished("trip-a"))
        await waitUntil("the export to finish") { coordinator.running == nil }

        let model = RecapModel(
            tripId: "trip-a", config: AppConfig.loadOrDie(),
            repository: TripRepository(database: try AppDatabase.inMemory()),
            coordinator: coordinator
        )
        let runsBefore = SpyExportJob.runs
        model.exportAgain()
        XCTAssertEqual(model.phase, .idle, "export again must land on the form")
        XCTAssertFalse(coordinator.isRendering(tripId: "trip-a"))
        XCTAssertEqual(SpyExportJob.runs, runsBefore, "no render may start until Export is tapped")
    }
}

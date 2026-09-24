@testable import Kamome
import KamomePersistence
import XCTest

/// **Deleting a trip stops its export first** (arch review 2026-09-24, P0-2).
///
/// The export outlives its screen, so Home's swipe can reach a trip whose film
/// is still rendering. Left running, the render finished into a deleted trip:
/// the file moved into `Films/`, the row was refused, and the file was orphaned.
@MainActor
final class TripDeletionTests: XCTestCase {
    private func request(_ tripId: String) -> RecapExportRequest {
        RecapExportRequest(tripId: tripId, photosEnabled: true, format: .mp4, appearance: .dark)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }

    private func repositoryHolding(_ title: String) throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try repository.saveCompletedTrip(
            title: title, startedAt: 0, endedAt: 3_600, segments: [], stops: []
        )
        return (repository, tripId)
    }

    func testDeletingTheTripBeingRenderedCancelsItsExport() async throws {
        let (repository, tripId) = try repositoryHolding("Rendering")
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request(tripId), job: job)
        await waitUntil { job.hasStarted }

        XCTAssertTrue(TripDeletion.delete(tripId: tripId, repository: repository, exports: coordinator))

        XCTAssertTrue(job.isCancelled, "the render must stop before it stores a film for a deleted trip")
        XCTAssertNil(try repository.detail(tripId: tripId), "the trip itself is still deleted")
        job.complete(.cancelled)
        await waitUntil { coordinator.running == nil }
    }

    func testDeletingAnotherTripLeavesTheRenderAlone() async throws {
        let (repository, tripId) = try repositoryHolding("Idle")
        let coordinator = RecapExportCoordinator()
        let job = SpyExportJob()
        coordinator.start(request: request("some-other-trip"), job: job)
        await waitUntil { job.hasStarted }

        XCTAssertTrue(TripDeletion.delete(tripId: tripId, repository: repository, exports: coordinator))

        XCTAssertFalse(job.isCancelled, "only the deleted trip's export stops")
        job.complete(.cancelled)
        await waitUntil { coordinator.running == nil }
    }
}

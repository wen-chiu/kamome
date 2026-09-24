import Foundation
import KamomeConfig
import KamomePersistence

/// **Deleting a trip stops everything still working on it first**
/// (arch review 2026-09-24, P0-2).
///
/// The export outlives its screen by design (ADR 2026-09-10), so a trip can be
/// swiped away on Home while its film is still rendering. The render then
/// finished into a trip that no longer existed: the MP4 was moved into
/// `Films/`, the `film` row was refused by the foreign key, and the file stayed
/// with nothing listing it. Routing kept spending the Worker's quota on legs
/// that were gone.
///
/// One function for every delete, so Home and Discovery cannot drift apart
/// again (they were two copies of the same three lines). Cancelling is enough:
/// the export checks its flag once more on the main actor before it stores a
/// film (`RecapExportJob.render`), and this runs on the main actor too, so no
/// store can land between the cancel and the delete.
@MainActor
enum TripDeletion {
    /// Returns whether the trip is gone. A failure is logged and reported
    /// rather than swallowed — the row is still there and the screen should
    /// keep showing it.
    @discardableResult
    static func delete(
        tripId: String,
        repository: TripRepository,
        exports: RecapExportCoordinator = .shared,
        routing: RouteMatchCoordinator = .shared
    ) -> Bool {
        exports.cancel(tripId: tripId)
        routing.cancel(tripId: tripId)
        let films: [FilmRecord]
        do {
            films = try repository.deleteTrip(tripId: tripId)
        } catch {
            KamomeLog.recap.error("trip deletion failed: \(error)")
            return false
        }
        FilmStore.deleteFiles(films: films)
        exports.clearOutcome(tripId: tripId)
        return true
    }
}

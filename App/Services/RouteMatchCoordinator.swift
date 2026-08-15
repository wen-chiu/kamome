import Foundation
import KamomeConfig
import KamomePersistence
import Observation

/// **One routing run per trip, and one answer about it** (2026-08-15).
///
/// Matching used to be awaited inside `ImportService.importTrip`, which is what
/// froze the first outside install: the sheet held the user until every leg had
/// timed out. Detaching it fixes the freeze and creates a second problem —
/// import no longer finishes before the user can tap the film button, and
/// `RecapModel` fires matching too. Two runs then execute over one trip.
///
/// **That is not a data race, and it was checked rather than assumed.**
/// `AppDatabase` is a GRDB `DatabaseQueue`, which serialises every read and
/// write; `setMatchedPolyline` is a one-row, one-column UPDATE that does not
/// read the row first; and `matchTrip` never writes nil, so no run can un-match
/// what another matched. Concurrent runs can only do the same work twice and
/// agree on the result.
///
/// It is still worth preventing, for two reasons that are about the product
/// rather than the database: a *per-run* budget is not the per-trip budget
/// `matching.trip_budget_s` promises, and two runs produce two verdicts for one
/// trip — one possibly "rate-limited" and the other "fine" — when the UI can
/// only show one. So the fix is single-flight ownership, not a lock: a second
/// caller **joins** the run in progress and gets its report.
@MainActor
@Observable
final class RouteMatchCoordinator {
    /// One shared owner, because the whole point is that two call sites cannot
    /// each start their own run.
    static let shared = RouteMatchCoordinator()

    /// How far a run has got, for a UI that no longer blocks on it.
    struct Progress: Equatable {
        let completed: Int
        let total: Int
    }

    private(set) var progress: [String: Progress] = [:]
    /// The last finished run's verdict per trip — what S5 shows the user.
    private(set) var reports: [String: RouteMatchReport] = [:]

    private var running: [String: Task<RouteMatchReport, Never>] = [:]
    private var flags: [String: CancelFlag] = [:]

    /// Set on main, read from the routing task between legs — the same
    /// lock-guarded shape `RecapModel` uses for the render, and for the same
    /// reason: the worker cannot make an actor hop mid-loop.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    private init() {}

    /// Starts routing if nothing is running for this trip, and returns without
    /// waiting. The import path's call — the trip is already saved and viewable,
    /// and roads arrive when they arrive.
    func start(tripId: String, service: RouteMatchService) {
        _ = run(tripId: tripId, service: service)
    }

    /// The finished report, waiting for a run already in flight rather than
    /// starting a second one. The recap path's call: the film should follow
    /// roads if roads are on their way.
    @discardableResult
    func result(tripId: String, service: RouteMatchService) async -> RouteMatchReport {
        await run(tripId: tripId, service: service).value
    }

    /// Stops the run at its next leg boundary. Remaining legs stay raw and
    /// dashed — a state the film already knows how to draw (PD-2).
    func cancel(tripId: String) {
        flags[tripId]?.set()
    }

    /// Whether a run is in flight for this trip — what a progress row observes.
    func isRunning(_ tripId: String) -> Bool {
        running[tripId] != nil
    }

    // MARK: - Single flight

    private func run(tripId: String, service: RouteMatchService) -> Task<RouteMatchReport, Never> {
        if let existing = running[tripId] { return existing }

        let flag = CancelFlag()
        flags[tripId] = flag
        progress[tripId] = Progress(completed: 0, total: 0)

        let task = Task<RouteMatchReport, Never> { [weak self] in
            // Off the main actor: the run reads the trip and waits on a network
            // provider, and neither belongs on the thread drawing the UI. Same
            // shape `TrackingSession.end` already uses.
            let report = await Task.detached(priority: .utility) {
                await service.matchTrip(
                    tripId: tripId,
                    shouldContinue: { !flag.isSet },
                    progress: { completed, total in
                        Task { @MainActor in
                            self?.progress[tripId] = Progress(completed: completed, total: total)
                        }
                    }
                )
            }.value
            await MainActor.run {
                self?.finish(tripId: tripId, report: report)
            }
            return report
        }
        running[tripId] = task
        return task
    }

    private func finish(tripId: String, report: RouteMatchReport) {
        running[tripId] = nil
        flags[tripId] = nil
        progress[tripId] = nil
        reports[tripId] = report
    }
}

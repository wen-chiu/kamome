import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import Observation

/// **One export at a time, and it outlives the screen that started it**
/// (Chiu 2026-09-10, Phase 4 closeout step 2).
///
/// The export used to live in `RecapModel`, held as `@State` inside `RecapView`'s
/// sheet. Closing the sheet deallocated the model and the Done button called
/// `cancel()` first, so a render of a minute or more pinned the user to one
/// screen — with `interactiveDismissDisabled` as the only thing standing between
/// them and a half-written file plus a leaked background assertion.
///
/// **This is the shape `RouteMatchCoordinator` already established here**, and
/// deliberately not a new one: a `@MainActor` coordinator that outlives every
/// view, so a second caller **joins** the work in flight instead of starting a
/// second one. Two differences, both of which are the point:
///
///  - Single flight is **app-wide, not per trip.** Routing two trips at once
///    only wastes quota. Exporting two at once means two `AVAssetWriter`s and
///    two snapshotter streams on a phone, which is a crash rather than a
///    slowdown. With a back button the user *can* open another trip and tap
///    Export, so a second request is joined when it is the same trip and
///    refused when it is not. Never started.
///  - It owns `ExportLifecycleGuard`, which the model used to hold. The guard is
///    taken in `start` and released in `finish`, and `finish` is the only exit —
///    so finish, cancel and failure release it structurally rather than by three
///    call sites remembering to. Expiry releases it inside the guard itself.
///
/// **What this does not do, and no copy may say it does.** The export does not
/// survive leaving the *app*: `AVAssetWriter` cannot resume across process
/// death, and checkpointed segments are a project rather than this step
/// (`ExportLifecycleGuard`). The promise is exactly: leave this screen, stay in
/// the app, the screen stays awake.
@MainActor
@Observable
final class RecapExportCoordinator {
    /// One shared owner, because the whole point is that two screens cannot each
    /// start their own render.
    static let shared = RecapExportCoordinator()

    /// The single export in flight, and everything a screen elsewhere in the app
    /// needs to draw it without owning it.
    struct Running: Equatable {
        let request: RecapExportRequest
        var fraction: Double = 0
        /// Published as the run learns them rather than at the end: both are
        /// findings the export screen shows *while* rendering, and both used to
        /// die with the model.
        var routing: RouteMatchReport?
        var photoShortfall: PhotoLibraryPhotoResolver.WarmSummary?

        var tripId: String { request.tripId }
    }

    /// What a start request did. Returned rather than thrown: a refusal is an
    /// ordinary answer the screen shows as a sentence, not an error.
    enum StartResult: Equatable {
        case started
        case joined
        /// Another trip is rendering. Carries which, so the screen can say so.
        case refused(busyTripId: String)
    }

    private(set) var running: Running?
    /// The last finished export per trip. This is what makes reopening a trip
    /// after its film landed show the film rather than an idle Export button —
    /// nothing is lost because nobody was looking.
    private(set) var outcomes: [String: RecapExportOutcome] = [:]

    private var task: Task<Void, Never>?
    private var cancelFlag = ExportCancelFlag()
    private let lifecycle: ExportLifecycleGuard

    /// `shared` is the app's one owner. The initialiser is reachable so tests
    /// can drive an instance with a fake lifecycle platform; nothing in the app
    /// constructs a second one.
    init(lifecycle: ExportLifecycleGuard? = nil) {
        // Built in the body, not as a default argument: a default argument is
        // evaluated in a nonisolated context and the guard is `@MainActor`.
        self.lifecycle = lifecycle ?? ExportLifecycleGuard()
    }

    // MARK: - Reading, from anywhere

    func isRendering(tripId: String) -> Bool { running?.tripId == tripId }

    /// The in-flight state for this trip, or nil when the trip is not the one
    /// rendering. A screen asks about its own trip and gets nothing back for
    /// somebody else's.
    func running(tripId: String) -> Running? {
        running?.tripId == tripId ? running : nil
    }

    func outcome(tripId: String) -> RecapExportOutcome? { outcomes[tripId] }

    /// Forgets a finished outcome, returning the trip to idle — what "Export
    /// again" and a film deletion do. Never touches a run in flight.
    func clearOutcome(tripId: String) {
        guard !isRendering(tripId: tripId) else { return }
        outcomes[tripId] = nil
    }

    // MARK: - Single flight

    /// Starts the export, joins the one already running for this trip, or
    /// refuses because a different trip is rendering. **It never starts a
    /// second**, which is the whole contract of this type.
    @discardableResult
    func start(request: RecapExportRequest, job: RecapExportRunning) -> StartResult {
        if let running {
            guard running.tripId == request.tripId else {
                KamomeLog.recap.notice(
                    "export refused: a film is already rendering — one export at a time"
                )
                return .refused(busyTripId: running.tripId)
            }
            return .joined
        }

        outcomes[request.tripId] = nil
        cancelFlag = ExportCancelFlag()
        running = Running(request: request)
        let flag = cancelFlag
        // Taken before the render starts and released in `finish` below, which
        // every exit goes through. On expiry the export cancels itself at a
        // frame boundary rather than being suspended mid-write.
        lifecycle.begin {
            KamomeLog.recap.error("export: the background assertion expired — cancelling at the next frame")
            flag.set()
        }
        let channel = RecapExportChannel(
            progress: { [weak self] fraction in self?.running?.fraction = fraction },
            routing: { [weak self] report in self?.running?.routing = report },
            photoShortfall: { [weak self] summary in self?.running?.photoShortfall = summary },
            shouldContinue: { !flag.isSet }
        )
        task = Task { [weak self] in
            let outcome = await job.run(channel)
            self?.finish(tripId: request.tripId, outcome: outcome)
        }
        return .started
    }

    /// Stops the render at its next frame boundary. An explicit user action —
    /// dismissing the export screen does not do this, and has not since
    /// 2026-09-10. Naming the trip so a stale screen cannot cancel a run that
    /// has already moved on to another one.
    func cancel(tripId: String) {
        guard isRendering(tripId: tripId) else { return }
        cancelFlag.set()
    }

    /// **The only exit.** Finish, cancel and failure all arrive here, so the
    /// lifecycle guard is released by structure rather than by three call sites
    /// remembering to.
    private func finish(tripId: String, outcome: RecapExportOutcome) {
        lifecycle.end()
        running = nil
        task = nil
        outcomes[tripId] = outcome
    }

    /// Whether the screen is currently pinned awake — read by the exit-path
    /// tests, which is the only way the four paths can be told apart.
    var isHoldingLifecycle: Bool { lifecycle.isHolding }
}

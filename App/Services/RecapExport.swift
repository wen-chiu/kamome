import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence

/// What one export is asked to make — the composition boundary's inputs, fixed
/// at the tap and constant for the whole render.
///
/// **Everything that can vary is in here on purpose** (`Docs/decisions.md`
/// 2026-08-15): export variation enters as an explicit value chosen at the tap
/// and held, never sampled from the environment while rendering. `appearance` is
/// the case that ADR was written about — ambient device state, so left unbound
/// it is a film that changes if the user toggles dark mode mid-render.
///
/// It is also what lets a screen reopened mid-render show the settings the
/// **running** film is using rather than its own fresh defaults.
struct RecapExportRequest: Equatable, Sendable {
    let tripId: String
    /// Photo overlays only (decisions.md 2026-07-18 recap-chrome, Chiu): off
    /// removes stop photo cards; title/end cards always render.
    let photosEnabled: Bool
    let format: RecapExportFormat
    let appearance: RecapAppearance
}

enum RecapExportFormat: String, CaseIterable, Equatable, Sendable {
    case mp4
    case gif
}

/// How one export ended. Three cases, because the screen says three different
/// things — and because `RecapExportCoordinator` releases the lifecycle guard on
/// all three through one exit.
enum RecapExportOutcome: Equatable, Sendable {
    /// The film is a record and a file on disk before this is published, so a
    /// completion nobody was looking at loses nothing. `fileURL` is resolved
    /// once here, at the point it is known good.
    case finished(film: FilmRecord, fileURL: URL)
    case cancelled
    case failed(message: String)
}

/// Where a running export is, in the order `RecapExportJob.run` goes through
/// them (Chiu 2026-09-26, S5 review item 2). Said by the job, never inferred by
/// the screen from which findings have arrived — that would be the call order
/// of `run` leaking into a view as an unwritten contract.
///
/// Three, because those are the waits a person can feel. Map tiles are fetched
/// *inside* the frame loop, interleaved with compositing, so "drawing the map"
/// is not a stage of its own; compose and plan are local and brief, so they
/// belong to the photos step that follows them.
enum RecapExportStage: Equatable, Sendable {
    /// Road reconstruction — the one step that may wait on the network.
    case findingRoads
    /// Composing the film and loading its photographs, iCloud included.
    case preparingPhotos
    /// Frames: the only stage `progress` measures.
    case drawing
}

/// What a running export tells its owner. A struct of closures rather than a
/// delegate: the coordinator is the only owner there will ever be, and this
/// keeps the job's dependency on it to six functions.
@MainActor
struct RecapExportChannel {
    var stage: (RecapExportStage) -> Void
    var progress: (Double) -> Void
    var routing: (RouteMatchReport) -> Void
    var photoShortfall: (PhotoLibraryPhotoResolver.WarmSummary?) -> Void
    /// The iCloud download phase before the render: nil when there is nothing to
    /// download or the phase is over.
    var photoPreload: (PhotoLibraryPhotoResolver.PreloadProgress?) -> Void
    /// Read from the render thread every frame — see `ExportCancelFlag`.
    var shouldContinue: @Sendable () -> Bool
}

/// One export, as the coordinator sees it: something that runs to an outcome,
/// reports as it goes, and stops when told.
///
/// **Why this is a protocol** (`Arch.md` §2 — what dependency does it protect?).
/// It keeps the coordinator's two rules — one export at a time, and the
/// lifecycle guard released on every exit — independent of `ExportEngine` and
/// the database. Without it the tests for those rules would each need a real
/// multi-minute `AVAssetWriter` render, which is to say they would not exist.
/// `RecapExportJob` is the only production conformer.
@MainActor
protocol RecapExportRunning {
    func run(_ channel: RecapExportChannel) async -> RecapExportOutcome
}

/// Set on main, read from the render thread every frame — a plain `Bool` would
/// need actor hops the render loop cannot make. The same shape
/// `RouteMatchCoordinator` uses between legs, for the same reason.
final class ExportCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

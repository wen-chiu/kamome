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

/// What a running export tells its owner. A struct of closures rather than a
/// delegate: the coordinator is the only owner there will ever be, and this
/// keeps the job's dependency on it to four functions.
@MainActor
struct RecapExportChannel {
    var progress: (Double) -> Void
    var routing: (RouteMatchReport) -> Void
    var photoShortfall: (PhotoLibraryPhotoResolver.WarmSummary?) -> Void
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

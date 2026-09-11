import Foundation
import UIKit

/// Keeps a running export alive through ordinary iOS behaviour (2026-08-15).
///
/// **Two things kill a render that is otherwise working**, and neither is a bug
/// in the render: the screen locks after the idle timer, and the user switches
/// away for a moment. An export runs for a minute or more — **65.6 s of render
/// for a 60.0 s film, 33.3 MB out** (measured 2026-09-10) — so both happen
/// routinely, and the user's only evidence is a film that never arrived.
///
/// ⚠️ **That measurement is SIMULATOR / Apple Maps / one trip.** It is not D2 and
/// not D3: no device figure exists, because the device session has never been
/// run (`Docs/release-readiness.md` Tier 3). It is also a **"before"** — the
/// export substrate is leaving Apple Maps for OpenFreeMap + MapLibre (ADR
/// 2026-09-09), and the number is expected to move. The figures this comment
/// used to carry — 270 s and 600 s — were **pre-reprojection**, from the
/// 4.4–9.5 min era `RecapRenderLoop` names; they described a render that no
/// longer exists.
///
/// So: hold the screen awake while a render is in flight, and take a background
/// task assertion so a brief app switch does not suspend the process mid-frame.
///
/// **What this deliberately is not.** It is not resumable export and it is not
/// true background rendering. `AVAssetWriter` cannot resume across process
/// death, so surviving a real termination means re-architecting around
/// checkpointed segments — a project, and not one the current phase needs. The
/// assertion buys the seconds iOS grants for a switch, nothing more; when it
/// expires the export is cancelled cleanly rather than left half-written.
///
/// This is what bounds the promise `RecapExportCoordinator` makes and the copy
/// the export screen is allowed to show: **leave the screen, stay in the app**
/// (Chiu 2026-09-10).
@MainActor
final class ExportLifecycleGuard {
    /// The three platform effects, behind a seam.
    ///
    /// **Why a seam rather than calling `UIApplication` directly.** The rule this
    /// class exists to keep is *released on every exit — finish, cancel, failure,
    /// expiry* — and the fourth of those is fired by iOS reclaiming an assertion,
    /// which no test can provoke. Without this, the one exit path most likely to
    /// leak a pinned screen is the one nothing can assert.
    struct Platform {
        var setIdleTimerDisabled: (Bool) -> Void
        var beginTask: (@escaping () -> Void) -> UIBackgroundTaskIdentifier
        var endTask: (UIBackgroundTaskIdentifier) -> Void

        static let uiKit = Platform(
            setIdleTimerDisabled: { UIApplication.shared.isIdleTimerDisabled = $0 },
            beginTask: { expiry in
                UIApplication.shared.beginBackgroundTask(withName: "kamome.recap.export", expirationHandler: expiry)
            },
            endTask: { UIApplication.shared.endBackgroundTask($0) }
        )
    }

    private let platform: Platform
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Called if iOS takes the assertion back before the export finishes, so the
    /// caller can stop at a frame boundary instead of being killed mid-write.
    private var onExpiry: (() -> Void)?

    init(platform: Platform = .uiKit) {
        self.platform = platform
    }

    /// Whether an assertion is currently held. The screen is pinned awake for
    /// exactly as long as this is true, which is what the exit-path tests read.
    var isHolding: Bool { backgroundTask != .invalid }

    /// Idempotent: starting twice holds one assertion, so a repeated export
    /// cannot leak one.
    func begin(onExpiry: @escaping () -> Void) {
        guard backgroundTask == .invalid else { return }
        self.onExpiry = onExpiry
        platform.setIdleTimerDisabled(true)
        backgroundTask = platform.beginTask { [weak self] in
            // iOS is reclaiming the assertion. Tell the export first, then let
            // go — an expiry handler that does not end its own task is killed.
            self?.onExpiry?()
            self?.end()
        }
    }

    /// Must be called on **every** exit from the export — finish, cancel and
    /// failure alike. A screen that never sleeps again is a worse bug than the
    /// one this fixes, and it is invisible until the battery is gone.
    func end() {
        guard backgroundTask != .invalid else { return }
        platform.setIdleTimerDisabled(false)
        platform.endTask(backgroundTask)
        backgroundTask = .invalid
        onExpiry = nil
    }

    deinit {
        // An owner deallocated mid-export must not leave the screen pinned
        // awake. The identifier and the platform are captured by value because
        // `self` is already going away.
        let task = backgroundTask
        let platform = platform
        guard task != .invalid else { return }
        Task { @MainActor in
            platform.setIdleTimerDisabled(false)
            platform.endTask(task)
        }
    }
}

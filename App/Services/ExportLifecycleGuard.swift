import Foundation
import UIKit

/// Keeps a running export alive through ordinary iOS behaviour (2026-08-15).
///
/// **Two things kill a render that is otherwise working**, and neither is a bug
/// in the render: the screen locks after the idle timer, and the user switches
/// away for a moment. An export runs for minutes — 270 s and 600 s on the two
/// measured device films — so both happen routinely, and the user's only
/// evidence is a film that never arrived.
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
@MainActor
final class ExportLifecycleGuard {
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Called if iOS takes the assertion back before the export finishes, so the
    /// caller can stop at a frame boundary instead of being killed mid-write.
    private var onExpiry: (() -> Void)?

    /// Idempotent: starting twice holds one assertion, so a repeated export
    /// cannot leak one.
    func begin(onExpiry: @escaping () -> Void) {
        guard backgroundTask == .invalid else { return }
        self.onExpiry = onExpiry
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "kamome.recap.export") { [weak self] in
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
        UIApplication.shared.isIdleTimerDisabled = false
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        onExpiry = nil
    }

    deinit {
        // A model deallocated mid-export must not leave the screen pinned awake.
        // `UIApplication` work has to happen on the main actor; the identifier is
        // captured by value because `self` is already going away.
        let task = backgroundTask
        guard task != .invalid else { return }
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

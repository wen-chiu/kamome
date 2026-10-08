import Foundation
import KamomeConfig
import Observation
import UIKit

/// Opens what the app needs from disk **only once the phone can read it** (#245),
/// and **says so when it cannot** (ADR 2026-10-08).
///
/// `kamome.sqlite` and the recording journal carry the default protection class,
/// `completeUntilFirstUserAuthentication`: unreadable from power-on until the
/// first unlock. A recording keeps significant-change and region monitoring on
/// for the whole trip, and either can relaunch a terminated app in the background
/// — so a phone restarted mid-trip and left locked could wake Kamome into a
/// database open that fails.
///
/// So the open waits. With protected data available it happens at once, in
/// `KamomeApp.init`, exactly as before. Without it, nothing is opened and the
/// open runs on the first of `protectedDataDidBecomeAvailable` or the app
/// becoming active. The journal then recovers the recording as it would after
/// any other interruption (`TrackingSession.recoverInterruptedRecording`).
///
/// **An open that fails with data available is not retried on its own and not
/// worked around.** It is held as `failure` for `DatabaseFailureView` to show,
/// with a retry the person presses — Chiu 2026-10-08: 「改成顯示錯誤畫面」. It
/// used to be a `fatalError`, which on a full disk or a damaged file meant a
/// crash on every launch and no way out but deleting the app, and the trips
/// with it. Nothing here deletes or replaces the file.
///
/// Generic over what is opened so the waiting is testable without a database.
@MainActor
@Observable
final class ProtectedDataLaunch<Value: AnyObject> {
    private(set) var value: Value?
    /// The failed open's `domain · code`, for the screen and a tester's
    /// screenshot — never the description, which names a file path.
    private(set) var failure: String?

    @ObservationIgnored private let isAvailable: @MainActor () -> Bool
    @ObservationIgnored private let open: () throws -> Value
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let center: NotificationCenter

    init(
        isAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        center: NotificationCenter = .default,
        open: @escaping () throws -> Value
    ) {
        self.isAvailable = isAvailable
        self.open = open
        self.center = center
        if isAvailable() {
            attempt()
            return
        }
        // Fixed words, no place (§0).
        KamomeLog.storage.notice("launch: protected data unavailable (locked since power-on) — opening on first unlock")
        for name in [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.openIfAvailable() }
            })
        }
    }

    /// The failure screen's button: one more open, nothing else.
    func retry() {
        guard value == nil, failure != nil else { return }
        attempt()
    }

    private func openIfAvailable() {
        guard value == nil, failure == nil, isAvailable() else { return }
        observers.forEach(center.removeObserver)
        observers = []
        KamomeLog.storage.notice("launch: protected data available — opening")
        attempt()
    }

    private func attempt() {
        do {
            value = try open()
            failure = nil
        } catch {
            let bridged = error as NSError
            let code = "\(bridged.domain) · \(bridged.code)"
            failure = code
            KamomeLog.storage.error("launch: the database failed to open — \(code, privacy: .public): \(error)")
        }
    }
}

import Foundation
import KamomeConfig
import Observation
import UIKit

/// Opens what the app needs from disk **only once the phone can read it** (#245).
///
/// `kamome.sqlite` and the recording journal carry the default protection class,
/// `completeUntilFirstUserAuthentication`: unreadable from power-on until the
/// first unlock. A recording keeps significant-change and region monitoring on
/// for the whole trip, and either can relaunch a terminated app in the
/// background — so a phone restarted mid-trip and left locked can wake Kamome
/// into a launch whose database open fails, and `openDatabaseOrDie` crashes it.
///
/// So the open waits. With protected data available it happens at once, in
/// `KamomeApp.init`, exactly as before. Without it, nothing is opened and the
/// open runs on the first of `protectedDataDidBecomeAvailable` or the app
/// becoming active. The journal then recovers the recording as it would after
/// any other interruption (`TrackingSession.recoverInterruptedRecording`).
///
/// **Not a fallback for a database that cannot open.** With protected data
/// available, a failed open still crashes the launch — the same `fatalError`,
/// the same message. Whether that should become a screen is Chiu's (#245).
///
/// Generic over what is opened so the waiting is testable without a database.
@MainActor
@Observable
final class ProtectedDataLaunch<Value: AnyObject> {
    private(set) var value: Value?

    @ObservationIgnored private let isAvailable: @MainActor () -> Bool
    @ObservationIgnored private let open: () -> Value
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let center: NotificationCenter

    init(
        isAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        center: NotificationCenter = .default,
        open: @escaping () -> Value
    ) {
        self.isAvailable = isAvailable
        self.open = open
        self.center = center
        if isAvailable() {
            value = open()
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

    private func openIfAvailable() {
        guard value == nil, isAvailable() else { return }
        observers.forEach(center.removeObserver)
        observers = []
        KamomeLog.storage.notice("launch: protected data available — opening")
        value = open()
    }
}

@testable import Kamome
import UIKit

// The two doubles `RecapExportCoordinatorTests` drives the coordinator with.
//
// In their own file so the test class stays under SwiftLint's type-body limit,
// and because both are about *not* doing the real thing — no render, no UIKit —
// which is what makes the coordinator's rules testable at all.

/// A stand-in for `RecapExportJob` that never renders. It parks inside
/// `run` until the test decides how the export ends, which is what lets one
/// test hold four exports in flight and another assert the exact moment the
/// lifecycle guard is released.
@MainActor
final class SpyExportJob: RecapExportRunning {
    /// **The "never a second writer" counter.** `RecapExporter` opens its
    /// `AVAssetWriter` inside `run`, so a peak of 2 here is two writers and
    /// two snapshotter streams on one phone.
    static var live = 0
    static var peak = 0
    static var runs = 0

    static func resetCounters() {
        live = 0
        peak = 0
        runs = 0
    }

    private var channel: RecapExportChannel?
    private var continuation: CheckedContinuation<RecapExportOutcome, Never>?

    var hasStarted: Bool { channel != nil }
    /// What the render loop reads every frame.
    var isCancelled: Bool { !(channel?.shouldContinue() ?? true) }

    func run(_ channel: RecapExportChannel) async -> RecapExportOutcome {
        Self.live += 1
        Self.peak = max(Self.peak, Self.live)
        Self.runs += 1
        self.channel = channel
        let outcome = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        Self.live -= 1
        return outcome
    }

    func report(progress: Double) { channel?.progress(progress) }

    func complete(_ outcome: RecapExportOutcome) {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: outcome)
    }
}

/// `UIApplication`'s three effects, counted. The expiry handler is held so
/// the test can fire it — iOS reclaiming an assertion is the one exit path
/// no test could otherwise provoke.
final class FakePlatform {
    var idleTimerDisabled = false
    var heldAssertions = 0
    var expiry: (() -> Void)?
    private var nextIdentifier = 1

    var platform: ExportLifecycleGuard.Platform {
        ExportLifecycleGuard.Platform(
            setIdleTimerDisabled: { self.idleTimerDisabled = $0 },
            beginTask: { handler in
                self.expiry = handler
                self.heldAssertions += 1
                self.nextIdentifier += 1
                return UIBackgroundTaskIdentifier(rawValue: self.nextIdentifier)
            },
            endTask: { _ in self.heldAssertions -= 1 }
        )
    }
}

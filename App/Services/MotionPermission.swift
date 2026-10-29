import CoreMotion
import Foundation
import KamomeTrackingEngine

/// The seam `TrackingSession` asks Motion & Fitness through, so a test can
/// answer the prompt (ADR 2026-10-29, #196).
protocol MotionPermissionProviding: AnyObject {
    /// True only while Motion & Fitness has never been answered.
    var needsAsking: Bool { get }
    /// Raises the prompt. `answered` runs on the main queue once the user has
    /// answered it, whichever the answer.
    func ask(answered: @escaping () -> Void)
}

/// Asks for Motion & Fitness while the record sheet is up, before a recording
/// starts (ADR 2026-10-29, #196). The recording used to ask by itself: on the
/// simulator, where activity is unavailable and nothing was started, the
/// prompt was raised by `stopActivityUpdates` at End Trip and came up on Home
/// after the trip (VERIFIED, tccd log). A phone, where it is available, asks
/// as the recording screen and Kamome's own card come up (INFERRED).
///
/// CoreMotion has no request call: a query is what raises the prompt, and its
/// handler runs once the prompt is answered (VERIFIED on the simulator,
/// 13–21 ms after the answer). The activities it returns are not wanted.
/// Nothing is read at creation (#235): this is built in `KamomeApp.init`.
final class MotionPermission: MotionPermissionProviding {
    private var asking: CMMotionActivityManager?

    var needsAsking: Bool {
        CMMotionActivityManager.authorizationStatus() == .notDetermined
    }

    func ask(answered: @escaping () -> Void) {
        let manager = CMMotionActivityManager()
        asking = manager
        manager.queryActivityStarting(from: .now, to: .now, to: .main) { [weak self] _, _ in
            self?.asking = nil
            answered()
        }
    }
}

/// **Motion & Fitness is asked as a recording starts**: after location, and
/// before the recording screen, while the record sheet is still up (Chiu
/// 2026-10-29, ADR 2026-10-29, #196). Asked here, the prompt can never land
/// on Kamome's own card, which comes with the recording screen. Either answer
/// starts the recording; without motion it records on GPS alone, as it always
/// has. Once answered it is never asked again, and the start is immediate.
final class MotionPromptHold {
    private let permission: MotionPermissionProviding
    /// Location is allowed and the prompt is up.
    private var vehicle: VehicleType?

    init(_ permission: MotionPermissionProviding) {
        self.permission = permission
    }

    /// Calls `start` with `vehicle` at once if the prompt was ever answered;
    /// otherwise asks, and calls it on the answer. A press while the prompt is
    /// up asks nothing more. An answer that never calls back (UNKNOWN on a
    /// phone) leaves the prompt answered, so the next press starts.
    func start(_ vehicle: VehicleType, with start: @escaping (VehicleType) -> Void) {
        guard permission.needsAsking else {
            self.vehicle = nil
            start(vehicle)
            return
        }
        guard self.vehicle == nil else { return }
        self.vehicle = vehicle
        permission.ask { [weak self] in
            guard let self, let vehicle = self.vehicle else { return }
            self.vehicle = nil
            start(vehicle)
        }
    }
}

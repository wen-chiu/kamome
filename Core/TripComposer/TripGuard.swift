import Foundation
import KamomeConfig

/// Phantom-trip guard (ADR 2026-07-16): the smoke drive saved a 2-second
/// zero-point trip, which is a degenerate input for the §4.5 speed-warped
/// camera path. A recording below either configured minimum is an accidental
/// start/stop and is discarded instead of persisted.
public enum TripGuard {
    public static func isPhantom(durationS: Double, distanceM: Double, config: TrackingConfig.Trip) -> Bool {
        durationS < config.minDurationS || distanceM < config.minDistanceM
    }
}

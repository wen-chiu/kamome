import Foundation
import KamomeConfig

/// §4.1: motion activity primary (confidence ≥ medium), speed heuristic
/// fallback. Stateless; sustain/confirm logic lives in TrackingEngine.
enum ModeClassifier {
    /// Returns the candidate mode for one instant, or nil when there is no
    /// evidence to change anything (stationary jitter — dwell detection owns
    /// that regime).
    static func classify(
        smoothedKmh: Double,
        activity: MotionActivity?,
        vehicle: VehicleType,
        config: TrackingConfig.Segmentation
    ) -> TransportMode? {
        if let activity, activity.isAtLeastMediumConfidence {
            switch activity.kind {
            case .automotive:
                // Transit heuristic outranks the activity label: CMMotion
                // reports trains as automotive too (§1.7).
                return smoothedKmh >= config.speedTransitMinKmh ? .transit : vehicle.automotiveMode
            case .cycling:
                return .cycle
            case .walking:
                return .walk
            case .stationary:
                return nil
            }
        }

        // Speed heuristic fallback (§4.1).
        if smoothedKmh < config.speedStationaryMaxKmh { return nil }
        if smoothedKmh >= config.speedTransitMinKmh { return .transit }
        if smoothedKmh > config.speedDriveMinKmh { return vehicle.automotiveMode }
        if smoothedKmh <= config.speedWalkMaxKmh { return .walk }
        // Mid band (walk_max..drive_min): §4.1 calls it "cycle/unknown" —
        // real evidence on a bicycle trip, inconclusive otherwise. "Can't
        // tell" must never confirm a segment change, so return no evidence
        // and let the current segment continue.
        return vehicle == .bicycle ? .cycle : nil
    }
}

/// Rolling mean speed over `speed_smoothing_window_s` — derived GPS speeds
/// are far too noisy to classify sample-by-sample.
struct SpeedSmoother {
    private var samples: [(ts: Double, mps: Double)] = []
    private let windowS: Double

    init(windowS: Double) {
        self.windowS = windowS
    }

    mutating func add(ts: Double, mps: Double) -> Double {
        samples.append((ts, mps))
        samples.removeAll { $0.ts < ts - windowS }
        let sum = samples.reduce(0) { $0 + $1.mps }
        return sum / Double(samples.count)
    }

    mutating func reset() {
        samples.removeAll()
    }
}

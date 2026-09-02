@testable import Kamome
import KamomeConfig
import XCTest

/// **The desk overrides a review render may apply**, split out of
/// `RecapDemoFilmTests` on 2026-09-02 to keep it inside its size budget — the
/// same split its assets, stop photos and substrate helpers already use.
///
/// Every one of these is an environment override, never a config edit: a film
/// judged from a working tree whose `TrackingConfig.json` had been altered is a
/// film nobody can reproduce.
extension RecapDemoFilmTests {
    /// The two review-only overrides, applied per run so a setting for one render
    /// never gets committed in `TrackingConfig.json`.
    ///
    /// `KAMOME_RECAP_MODE` picks **Variant A** (`full` — every clustered stop
    /// presented, no duration cap) against the shipped **Variant B**
    /// (`highlight`). `KAMOME_FORCE_DURATION_S` pins a length for a length
    /// experiment; it is marked temporary where it was introduced (2026-08-04).
    static func reviewConfig(_ base: TrackingConfig.Export) throws -> TrackingConfig.Export {
        var config = base
        if let requested = HarnessEnv.value("KAMOME_RECAP_MODE") {
            guard let mode = RecapMode(rawValue: requested) else {
                XCTFail("KAMOME_RECAP_MODE=\(requested) is not a RecapMode")
                throw CocoaError(.featureUnsupported)
            }
            config = config.withRecapMode(mode)
            print("KAMOME_RECAP_MODE \(requested)")
            // Variant A means "see the whole trip", and a stop with a beat but no
            // photograph is still empty to the viewer — so the allocator's zero
            // share, which is right for a highlight reel, is wrong here. Scoped to
            // the mode so Variant B's shipped 0.4 is untouched.
            //
            // Explicitly overridable so the *before* of this change stays
            // measurable: comparing Variant A against Variant B would have
            // compared two things at once.
            if case .full = mode {
                let share = HarnessEnv.value("KAMOME_ALLOCATION_ZERO_SHARE")
                    .flatMap(Double.init) ?? 0
                config = config.withAllocationZeroShare(share)
                print("KAMOME_ALLOCATION_ZERO_SHARE \(share) (Variant A)")
            }
        }
        if let beat = HarnessEnv.value("KAMOME_CROSSING_BEAT_S").flatMap(Double.init) {
            config = config.withCrossingBeatS(beat); print("KAMOME_CROSSING_BEAT_S \(beat)")
        }
        if let forced = HarnessEnv.value("KAMOME_FORCE_DURATION_S").flatMap(Double.init) {
            config = config.withTotalDuration(min: forced, max: forced)
            print("KAMOME_FORCE_DURATION_S \(forced)")
        }
        return config
    }
}

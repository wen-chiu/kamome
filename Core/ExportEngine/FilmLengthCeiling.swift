import Foundation
import KamomeConfig

extension TrackingConfig.Export {
    /// The most a film of `length` may run, before the person's own additions.
    public func durationCeilingS(for length: FilmLength) -> Double {
        switch length {
        case .short: return totalDurationMaxS
        case .standard: return standardDurationMaxS
        }
    }
}

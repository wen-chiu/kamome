import Foundation
import KamomeConfig

/// §2.3 adaptive sampling: what the location adapter should ask CoreLocation
/// for, given the current mode and speed. Pure lookup over config — the
/// per-vehicle presets come from §1.7.
public enum SamplingPolicyTable {
    /// nil means "GPS off" — dwell-paused state runs on region monitoring.
    public static func policy(
        state: TrackingEngine.State,
        mode: TransportMode,
        speedKmh: Double,
        vehicle: VehicleType,
        config: TrackingConfig
    ) -> TrackingConfig.SamplingPolicy? {
        guard state == .recording else { return nil }

        switch mode {
        case .walk:
            return config.sampling.walk
        case .drive, .scooter, .cycle, .transit, .unknown:
            let preset = preset(for: vehicle, config: config)
            return speedKmh >= preset.fastMinKmh ? preset.fast : preset.slow
        }
    }

    private static func preset(for vehicle: VehicleType, config: TrackingConfig) -> TrackingConfig.VehiclePreset {
        switch vehicle {
        case .car: return config.sampling.vehicles.car
        case .scooter: return config.sampling.vehicles.scooter
        case .bicycle: return config.sampling.vehicles.bicycle
        }
    }
}

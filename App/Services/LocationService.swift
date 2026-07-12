import CoreLocation
import CoreMotion
import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// Bridges CoreLocation/CoreMotion to the pure TrackingEngine and applies the
/// §2.3 adaptive sampling table to the location manager. The only file that
/// talks to CLLocationManager.
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onSample: ((LocationSample, MotionActivity?) -> Void)?

    private let manager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let config: TrackingConfig
    private var latestActivity: MotionActivity?
    private var currentFilterM: Double = -1

    init(config: TrackingConfig) {
        self.config = config
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = false // escalated after Always grant
        manager.pausesLocationUpdatesAutomatically = false // we manage pausing (§2.3)
    }

    func requestPermission() {
        // When In Use at first Start; Always escalation with a priming screen
        // is a device-test follow-up (§6).
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates(vehicle: VehicleType) {
        apply(policy: SamplingPolicyTable.policy(
            state: .recording, mode: .unknown, speedKmh: 0, vehicle: vehicle, config: config
        ))
        manager.startUpdatingLocation()
        startMotionUpdates()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        motionManager.stopActivityUpdates()
        latestActivity = nil
    }

    /// Re-applies the sampling table when the engine's mode/speed changes.
    func adapt(state: TrackingEngine.State, mode: TransportMode, speedKmh: Double, vehicle: VehicleType) {
        apply(policy: SamplingPolicyTable.policy(
            state: state, mode: mode, speedKmh: speedKmh, vehicle: vehicle, config: config
        ))
    }

    private func apply(policy: TrackingConfig.SamplingPolicy?) {
        guard let policy else {
            manager.stopUpdatingLocation()
            return
        }
        // Only "nearest_ten_meters" is in the shipped table; unknown names
        // fall back to it rather than silently burning battery.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if policy.distanceFilterM != currentFilterM {
            manager.distanceFilter = policy.distanceFilterM
            currentFilterM = policy.distanceFilterM
        }
    }

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let kind: MotionActivity.Kind?
            if activity.automotive {
                kind = .automotive
            } else if activity.cycling {
                kind = .cycling
            } else if activity.walking || activity.running {
                kind = .walking
            } else if activity.stationary {
                kind = .stationary
            } else {
                kind = nil
            }
            guard let kind else { return }
            self?.latestActivity = MotionActivity(
                kind: kind,
                isAtLeastMediumConfidence: activity.confidence != .low
            )
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            let sample = LocationSample(
                ts: location.timestamp.timeIntervalSince1970,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                hAccM: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                speedMps: location.speed >= 0 ? location.speed : nil,
                course: location.course >= 0 ? location.course : nil,
                altitudeM: location.verticalAccuracy >= 0 ? location.altitude : nil
            )
            onSample?(sample, latestActivity)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are expected (tunnels, airplane mode); the
        // engine simply sees no samples until fixes resume.
    }
}

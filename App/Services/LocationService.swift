import CoreLocation
import CoreMotion
import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// Bridges CoreLocation/CoreMotion to the pure TrackingEngine and applies the
/// §2.3 adaptive sampling table to the location manager. The only file that
/// talks to CLLocationManager.
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// How a dwell pause is executed given what CoreLocation can deliver (§2.3).
    enum DwellPausePlan: Equatable {
        /// GPS off; a region-exit event wakes tracking back up.
        case regionMonitoring
        /// Region events need Always authorization and hardware support —
        /// without them GPS stays on so the engine still sees the exit fix.
        case gpsFallback
    }

    static func dwellPausePlan(
        authorization: CLAuthorizationStatus,
        regionMonitoringAvailable: Bool
    ) -> DwellPausePlan {
        guard regionMonitoringAvailable, authorization == .authorizedAlways else { return .gpsFallback }
        return .regionMonitoring
    }

    var onSample: ((LocationSample, MotionActivity?) -> Void)?

    private static let dwellRegionIdentifier = "kamome.dwell.region"

    private let manager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let config: TrackingConfig
    private var latestActivity: MotionActivity?
    private var currentFilterM: Double = -1
    private var vehicle: VehicleType?
    private var isDwellRegionArmed = false
    /// Timestamp of the last delivered fix, for the silent-death watchdog
    /// (sampling.recovery_gap_s). nil right after (re)starting the standard
    /// session — the first fix after a restart never triggers recovery.
    private var lastDeliveryTs: Double?

    init(config: TrackingConfig) {
        self.config = config
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false // we manage pausing (§2.3)
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestPermission() {
        // When In Use at first Start (§6); the priming sheet escalates to
        // Always so tracking survives screen lock during an active trip.
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startUpdates(vehicle: VehicleType) {
        self.vehicle = vehicle
        applyBackgroundCapability()
        apply(policy: SamplingPolicyTable.policy(
            state: .recording, mode: .unknown, speedKmh: 0, vehicle: vehicle, config: config
        ))
        lastDeliveryTs = nil
        manager.startUpdatingLocation()
        // Trip-long safety net (2026-07-19 drive: the dwell region-exit wake
        // restarted GPS but iOS suspended the app ~10 s later, losing 32 min
        // of driving). Significant-change fixes cost ~nothing (§1.8) and keep
        // waking the app, so the recovery watchdog always gets another shot
        // at restarting a dead standard session.
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        startMotionUpdates()
    }

    func stopUpdates() {
        disarmDwellRegion()
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        motionManager.stopActivityUpdates()
        latestActivity = nil
        vehicle = nil
    }

    /// §2.3 dwell: turn GPS off and arm a region around the stop center so a
    /// region-exit event resumes tracking. When region events can't be
    /// delivered, GPS stays on instead — a paused trip must never be stranded
    /// waiting for an event that cannot come.
    func pauseForDwell(centerLat: Double, centerLon: Double) {
        let plan = Self.dwellPausePlan(
            authorization: manager.authorizationStatus,
            regionMonitoringAvailable: CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        )
        guard plan == .regionMonitoring else { return }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            radius: min(config.dwell.regionRadiusM, manager.maximumRegionMonitoringDistance),
            identifier: Self.dwellRegionIdentifier
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
        isDwellRegionArmed = true
        lastDeliveryTs = nil
        manager.stopUpdatingLocation()
    }

    /// The engine left dwell-pause on its own (a fix escaped the region —
    /// e.g. a significant-change fix arriving before, or instead of, the
    /// region-exit event). Bring GPS back up to match; no-op when the region
    /// was never armed (gpsFallback plan) or the exit event already handled it.
    func resumeActiveTracking() {
        resumeAfterDwell()
    }

    /// Re-applies the sampling table when the engine's mode/speed changes.
    func adapt(state: TrackingEngine.State, mode: TransportMode, speedKmh: Double, vehicle: VehicleType) {
        apply(policy: SamplingPolicyTable.policy(
            state: state, mode: mode, speedKmh: speedKmh, vehicle: vehicle, config: config
        ))
    }

    private func apply(policy: TrackingConfig.SamplingPolicy?) {
        // nil = dwell-paused. GPS off is pauseForDwell's call, not this one:
        // in the gpsFallback plan updates keep flowing while paused, and
        // stopping here would kill the trip's only way to detect the exit.
        guard let policy else { return }
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

    /// Requires UIBackgroundModes=[location] (declared). Works with When In
    /// Use (blue indicator pill) and silently with Always; tracking only ever
    /// runs during an explicit trip (§6 — that's the App Review case).
    private func applyBackgroundCapability() {
        let status = manager.authorizationStatus
        let authorized = status == .authorizedAlways || status == .authorizedWhenInUse
        manager.allowsBackgroundLocationUpdates = authorized
        manager.showsBackgroundLocationIndicator = true
    }

    /// Region exit (or a monitoring failure) while dwell-paused: put GPS back
    /// on so the engine sees the exit fix and reopens a segment.
    private func resumeAfterDwell() {
        guard isDwellRegionArmed else { return }
        disarmDwellRegion()
        guard let vehicle else { return }
        apply(policy: SamplingPolicyTable.policy(
            state: .recording, mode: .unknown, speedKmh: 0, vehicle: vehicle, config: config
        ))
        // Re-assert before restarting: this runs inside a short region-exit
        // background wake, and a session started without the background flag
        // in effect dies when the wake window closes — the 2026-07-19 drive
        // got exactly two fixes after resume, then 32 min of silence.
        applyBackgroundCapability()
        lastDeliveryTs = nil
        manager.startUpdatingLocation()
    }

    private func disarmDwellRegion() {
        isDwellRegionArmed = false
        for region in manager.monitoredRegions where region.identifier == Self.dwellRegionIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        applyBackgroundCapability()
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.dwellRegionIdentifier else { return }
        #if DEBUG
        DriveTestLog.shared.regionExited()
        #endif
        resumeAfterDwell()
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard region?.identifier == Self.dwellRegionIdentifier else { return }
        resumeAfterDwell()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let newest = locations.last, !isDwellRegionArmed, vehicle != nil {
            let ts = newest.timestamp.timeIntervalSince1970
            if let previous = lastDeliveryTs, ts - previous >= config.sampling.recoveryGapS {
                // The standard session died without any callback (iOS
                // suspended the app); this fix is a significant-change wake —
                // use its runtime window to bring the session back.
                applyBackgroundCapability()
                manager.startUpdatingLocation()
                #if DEBUG
                DriveTestLog.shared.gpsRecovered(gapS: ts - previous)
                #endif
            }
            lastDeliveryTs = ts
        }
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

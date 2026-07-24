import CoreLocation
import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer
import Observation

/// View model behind S1/S2: owns one recording's engine + location service,
/// and persists the result on End Trip.
@Observable
final class TrackingSession {
    private(set) var isRecording = false
    /// Drives the §6 Always-permission priming sheet on first recording.
    var needsAlwaysPriming = false
    private(set) var startedAt: Date?
    private(set) var traveledPath: [CLLocationCoordinate2D] = []
    private(set) var distanceM: Double = 0
    private(set) var currentMode: TransportMode = .unknown
    private(set) var stopCount = 0
    private(set) var trips: [TripRecord] = []

    let config: TrackingConfig
    let repository: TripRepository
    private var engine: TrackingEngine?
    private var locationService: LocationService?
    private var lastCoordinate: CLLocationCoordinate2D?

    init(config: TrackingConfig, repository: TripRepository) {
        self.config = config
        self.repository = repository
        refreshTrips()
    }

    func refreshTrips() {
        trips = (try? repository.allTrips()) ?? []
    }

    func start(vehicle: VehicleType, now: Date = .now) {
        guard !isRecording else { return }
        let engine = TrackingEngine(config: config, vehicle: vehicle)
        engine.start(at: now.timeIntervalSince1970)
        let service = LocationService(config: config)
        service.onSample = { [weak self] sample, activity in
            self?.consume(sample: sample, activity: activity)
        }
        service.requestPermission()
        service.startUpdates(vehicle: vehicle)

        self.engine = engine
        locationService = service
        needsAlwaysPriming = service.authorizationStatus != .authorizedAlways
        startedAt = now
        traveledPath = []
        distanceM = 0
        stopCount = 0
        currentMode = .unknown
        isRecording = true
        #if DEBUG
        DriveTestLog.shared.tripStarted(vehicle: vehicle.rawValue)
        #endif
    }

    func end(now: Date = .now) {
        guard isRecording, let engine else { return }
        locationService?.stopUpdates()
        engine.finish(at: now.timeIntervalSince1970)

        // Stops the live detector cannot see — silence gaps and walk visits
        // (ADR 2026-07-18) — are derived from the finished segments.
        let allStops = (engine.stops + StopDeriver.derive(
            segments: engine.segments, engineStops: engine.stops, config: config
        )).sorted { $0.arrivedAt < $1.arrivedAt }

        // Denormalized stats for the S1 card and S3 strip (§3 stats_json);
        // computed before saving so the phantom guard shares its distance.
        let stats = TripStats.compute(segments: engine.segments, stops: allStops, config: config)
        let durationS = now.timeIntervalSince(startedAt ?? now)
        if TripGuard.isPhantom(durationS: durationS, distanceM: stats.distanceM, config: config.trip) {
            self.engine = nil
            locationService = nil
            isRecording = false
            #if DEBUG
            DriveTestLog.shared.tripEnded(discardedAsPhantom: true)
            #endif
            return
        }

        let title = Self.defaultTitle(for: startedAt ?? now)
        let segments = engine.segments.map(Self.repositorySegment)
        let stops = allStops.map {
            TripRepository.NewStop(
                lat: $0.lat, lon: $0.lon,
                arrivedAt: $0.arrivedAt, departedAt: $0.departedAt,
                kind: $0.kind.rawValue
            )
        }
        if let tripId = try? repository.saveCompletedTrip(
            title: title,
            startedAt: (startedAt ?? now).timeIntervalSince1970,
            endedAt: now.timeIntervalSince1970,
            segments: segments,
            stops: stops
        ) {
            if let json = stats.jsonString() {
                try? repository.updateTripStats(tripId: tripId, statsJson: json)
            }
            // §4.4 matching, fire-and-forget: trip completion never waits on
            // it, and the recap path retries any segment left unmatched.
            let matcher = RouteMatchService(repository: repository, config: config)
            Task.detached(priority: .utility) {
                await matcher.matchTrip(tripId: tripId)
            }
        }

        self.engine = nil
        locationService = nil
        isRecording = false
        refreshTrips()
        #if DEBUG
        DriveTestLog.shared.tripEnded()
        #endif
    }

    func grantAlwaysPermission() {
        locationService?.requestAlwaysPermission()
        needsAlwaysPriming = false
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date.now.timeIntervalSince(startedAt)
    }

    private func consume(sample: LocationSample, activity: MotionActivity?) {
        guard let engine else { return }
        let wasDwellPaused = engine.state == .dwellPaused
        engine.process(sample, activity: activity)

        let coordinate = CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon)
        if let last = lastCoordinate {
            let step = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            distanceM += step
        }
        lastCoordinate = coordinate
        traveledPath.append(coordinate)
        currentMode = engine.currentMode ?? .unknown
        stopCount = engine.stops.count
        #if DEBUG
        if (engine.state == .dwellPaused) != wasDwellPaused {
            if wasDwellPaused {
                DriveTestLog.shared.dwellResumed()
            } else {
                DriveTestLog.shared.dwellPaused()
            }
        }
        #endif
        if engine.state == .dwellPaused, !wasDwellPaused, let stop = engine.stops.last {
            // §2.3: hand the stop center to the location layer so the resume
            // region is armed before GPS goes quiet.
            locationService?.pauseForDwell(centerLat: stop.lat, centerLon: stop.lon)
        } else {
            if wasDwellPaused, engine.state == .recording {
                // The engine resumed off a delivered fix; make sure the
                // location layer follows even if the region-exit event never
                // arrives (it may have been this very fix's SLC wake).
                locationService?.resumeActiveTracking()
            }
            locationService?.adapt(
                state: engine.state,
                mode: currentMode,
                speedKmh: (sample.speedMps ?? 0) * 3.6,
                vehicle: engine.vehicle
            )
        }
    }

    private static func repositorySegment(from segment: TrackingEngine.Segment) -> TripRepository.NewSegment {
        TripRepository.NewSegment(
            mode: segment.mode.rawValue,
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            points: segment.points.map {
                TripRepository.NewTrackpoint(
                    ts: $0.ts, lat: $0.lat, lon: $0.lon,
                    hAcc: $0.hAccM, speed: $0.speedMps, course: $0.course, altitude: $0.altitudeM
                )
            }
        )
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

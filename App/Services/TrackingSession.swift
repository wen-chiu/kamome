import CoreLocation
import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
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

    private let config: TrackingConfig
    private let repository: TripRepository
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
    }

    func end(now: Date = .now) {
        guard isRecording, let engine else { return }
        locationService?.stopUpdates()
        engine.finish(at: now.timeIntervalSince1970)

        let title = Self.defaultTitle(for: startedAt ?? now)
        let segments = engine.segments.map { segment in
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
        let stops = engine.stops.map {
            TripRepository.NewStop(lat: $0.lat, lon: $0.lon, arrivedAt: $0.arrivedAt, departedAt: $0.departedAt)
        }
        try? repository.saveCompletedTrip(
            title: title,
            startedAt: (startedAt ?? now).timeIntervalSince1970,
            endedAt: now.timeIntervalSince1970,
            segments: segments,
            stops: stops
        )

        self.engine = nil
        locationService = nil
        isRecording = false
        refreshTrips()
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
        locationService?.adapt(
            state: engine.state,
            mode: currentMode,
            speedKmh: (sample.speedMps ?? 0) * 3.6,
            vehicle: engine.vehicle
        )
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

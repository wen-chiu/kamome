import CoreLocation
import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer
import Observation

/// View model behind S1/S2: owns one recording's engine + location service,
/// and persists the result on End Trip.
///
/// **A recording survives the app** (2026-09-24). Every sample is written to
/// the `RecordingJournal` before the engine sees it, and a launch that finds a
/// journal replays it and carries on recording — whether the user reopened the
/// app or iOS relaunched it in the background on a significant location change.
/// Nothing asks: a relaunch in a pocket has no one to ask, and a recording the
/// user never ended is still a recording.
@Observable
final class TrackingSession {
    /// A recording that was carried on after the app was terminated mid-trip.
    struct Interruption: Equatable {
        /// From the last fix before the app died to the moment recording
        /// resumed — the stretch with no track.
        let gapS: Double
    }

    private(set) var isRecording = false
    /// Set when the current recording was recovered from its journal; S2 says
    /// so once, and the user dismisses it.
    var interruption: Interruption?
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
    private let journal: RecordingJournalFile?

    init(
        config: TrackingConfig,
        repository: TripRepository,
        journal: RecordingJournalFile? = RecordingJournalFile.defaultURL().map(RecordingJournalFile.init),
        now: Date = .now
    ) {
        self.config = config
        self.repository = repository
        self.journal = journal
        refreshTrips()
        recoverInterruptedRecording(now: now)
    }

    func refreshTrips() {
        trips = Stored.read("allTrips") { try repository.allTrips() } ?? []
    }

    /// Swipe-to-delete on the home list — the same `TripDeletion` Journey
    /// Discovery uses: the trip's export and routing stop, the trip row and its
    /// stored films go, the photographs never do.
    @MainActor
    func deleteTrip(_ tripId: String) {
        TripDeletion.delete(tripId: tripId, repository: repository)
        refreshTrips()
    }

    func start(vehicle: VehicleType, now: Date = .now) {
        guard !isRecording else { return }
        let engine = TrackingEngine(config: config, vehicle: vehicle)
        engine.start(at: now.timeIntervalSince1970)
        journal?.begin(.start(ts: now.timeIntervalSince1970, vehicle: vehicle))
        resetHUD()
        interruption = nil
        startLive(engine: engine, startedAt: now)
        #if DEBUG
        DriveTestLog.shared.tripStarted(vehicle: vehicle.rawValue)
        #endif
    }

    func end(now: Date = .now) {
        guard isRecording, let engine else { return }
        // Written first: if the save below never completes, the next launch
        // finds a trip that was ended and saves it, rather than resuming it.
        journal?.append(.end(ts: now.timeIntervalSince1970))
        locationService?.stopUpdates()
        engine.finish(at: now.timeIntervalSince1970)
        let outcome = save(engine: engine, startedAt: startedAt ?? now, endedAt: now)
        finishJournal(after: outcome)

        self.engine = nil
        locationService = nil
        isRecording = false
        interruption = nil
        refreshTrips()
        #if DEBUG
        DriveTestLog.shared.tripEnded(discardedAsPhantom: outcome == .phantom)
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

    // MARK: - Saving

    enum SaveOutcome: Equatable {
        case saved, phantom, failed
    }

    /// Persists a finished engine as a trip. The only writer of recorded trips:
    /// End Trip and a recovered, already-ended journal both come through here.
    private func save(engine: TrackingEngine, startedAt: Date, endedAt now: Date) -> SaveOutcome {
        // Stops the live detector cannot see — silence gaps and walk visits
        // (ADR 2026-07-18) — are derived from the finished segments.
        let allStops = (engine.stops + StopDeriver.derive(
            segments: engine.segments, engineStops: engine.stops, config: config
        )).sorted { $0.arrivedAt < $1.arrivedAt }

        // Denormalized stats for the S1 card and S3 strip (§3 stats_json);
        // computed before saving so the phantom guard shares its distance.
        let stats = TripStats.compute(segments: engine.segments, stops: allStops, config: config)
        let durationS = now.timeIntervalSince(startedAt)
        if TripGuard.isPhantom(durationS: durationS, distanceM: stats.distanceM, config: config.trip) {
            return .phantom
        }

        let title = Self.defaultTitle(for: startedAt)
        let segments = engine.segments.map(Self.repositorySegment)
        let stops = allStops.map {
            TripRepository.NewStop(
                lat: $0.lat, lon: $0.lon,
                arrivedAt: $0.arrivedAt, departedAt: $0.departedAt,
                kind: $0.kind.rawValue
            )
        }
        let tripId: String
        do {
            tripId = try repository.saveCompletedTrip(
                title: title,
                startedAt: startedAt.timeIntervalSince1970,
                endedAt: now.timeIntervalSince1970,
                segments: segments,
                stops: stops
            )
        } catch {
            // Why, not just that: `finishJournal` says the journal is kept.
            KamomeLog.storage.error("saveCompletedTrip failed: \(error)")
            return .failed
        }

        if let json = stats.jsonString() {
            Stored.write("updateTripStats") { try repository.updateTripStats(tripId: tripId, statsJson: json) }
        }
        // Recorded at creation for the same reason the importer does it.
        Stored.write("setTripVehicle") {
            try repository.setTripVehicle(tripId: tripId, vehicleId: LastVehicleChoice.forNewTrip())
        }
        // Home's card can show a place + flag without S3 ever being opened
        // (Chiu 2026-09-22) — see `TripJourneyNaming`.
        TripJourneyNaming.nameIfNeeded(tripId: tripId, repository: repository)
        // §4.4 matching, fire-and-forget: trip completion never waits on
        // it, and the recap path joins any run still going rather than
        // starting a second one over the same legs.
        let matcher = RouteMatchService(repository: repository, matching: config.matching)
        Task { @MainActor in
            RouteMatchCoordinator.shared.start(tripId: tripId, service: matcher)
        }
        return .saved
    }

    /// The journal goes once the trip is safely stored (or deliberately
    /// discarded). A failed save keeps it — with its end line, the next launch
    /// retries the save instead of losing the trip.
    private func finishJournal(after outcome: SaveOutcome) {
        switch outcome {
        case .saved, .phantom:
            journal?.remove()
        case .failed:
            journal?.close()
            KamomeLog.recording.error("save failed — the journal is kept and the next launch retries it")
        }
    }

    // MARK: - Recovery

    /// Picks up a recording the app was terminated in the middle of.
    ///
    /// Two cases, told apart by the journal's end line. **Ended** (End Trip was
    /// pressed, the save never completed) is saved as it ended. **Not ended** is
    /// resumed: the engine replayed to exactly where it was, GPS restarted, and
    /// the dwell region re-armed if it was sitting at a stop. The time the app
    /// was dead has no track; it reaches the trip as a silence gap, which
    /// `StopDeriver` reads the way it reads any other GPS silence.
    private func recoverInterruptedRecording(now: Date) {
        guard let journal, let entries = journal.read() else { return }
        guard let recovered = RecordingJournal.replay(entries, config: config) else {
            journal.remove()
            return
        }
        let startedAt = Date(timeIntervalSince1970: recovered.startedAt)

        if let endedAtTs = recovered.endedAt {
            recovered.engine.finish(at: endedAtTs)
            let outcome = save(
                engine: recovered.engine, startedAt: startedAt, endedAt: Date(timeIntervalSince1970: endedAtTs)
            )
            finishJournal(after: outcome)
            refreshTrips()
            KamomeLog.recording.notice("""
                recovery: saved an ended trip — \(recovered.samples.count, privacy: .public) samples, \
                \(String(describing: outcome), privacy: .public)
                """)
            return
        }

        resetHUD()
        for sample in recovered.samples { absorbIntoHUD(sample) }
        let lastFixTs = recovered.samples.last?.ts ?? recovered.startedAt
        let gapS = max(0, now.timeIntervalSince1970 - lastFixTs)
        interruption = Interruption(gapS: gapS)
        startLive(engine: recovered.engine, startedAt: startedAt)
        if recovered.engine.state == .dwellPaused, let stop = recovered.engine.stops.last {
            locationService?.pauseForDwell(centerLat: stop.lat, centerLon: stop.lon)
        }
        KamomeLog.recording.notice("""
            recovery: resumed a recording — \(recovered.samples.count, privacy: .public) samples, \
            \(recovered.engine.stops.count, privacy: .public) stops, \
            dwell-paused \(recovered.engine.state == .dwellPaused, privacy: .public), \
            gap \(Int(gapS), privacy: .public) s
            """)
    }

    // MARK: - Live

    /// Wires a started (or replayed) engine to a fresh location service.
    private func startLive(engine: TrackingEngine, startedAt: Date) {
        let service = LocationService(config: config)
        service.onSample = { [weak self] sample, activity in
            self?.consume(sample: sample, activity: activity)
        }
        service.requestPermission()
        service.startUpdates(vehicle: engine.vehicle)

        self.engine = engine
        locationService = service
        needsAlwaysPriming = service.authorizationStatus != .authorizedAlways
        self.startedAt = startedAt
        currentMode = engine.currentMode ?? .unknown
        stopCount = engine.stops.count
        isRecording = true
    }

    private func resetHUD() {
        traveledPath = []
        distanceM = 0
        lastCoordinate = nil
        stopCount = 0
        currentMode = .unknown
    }

    private func absorbIntoHUD(_ sample: LocationSample) {
        let coordinate = CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon)
        if let last = lastCoordinate {
            let step = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            distanceM += step
        }
        lastCoordinate = coordinate
        traveledPath.append(coordinate)
    }

    private func consume(sample: LocationSample, activity: MotionActivity?) {
        guard let engine else { return }
        // Journal before engine: a replay must see exactly what the engine saw.
        journal?.append(.sample(sample, activity))
        let wasDwellPaused = engine.state == .dwellPaused
        engine.process(sample, activity: activity)

        absorbIntoHUD(sample)
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

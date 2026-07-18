import Foundation
import KamomeConfig

/// The Phase 1 heart (§7): a synchronous state machine that turns a stream of
/// location samples (+ optional motion activities) into mode-typed segments
/// and detected stops.
///
///     idle → recording ⇄ dwellPaused → … → completed
///
/// Pure logic: no CoreLocation, no persistence, no clocks — callers push
/// samples (live adapter on device, GPX harness in tests) and read results.
public final class TrackingEngine {
    public enum State: Equatable {
        case idle, recording, dwellPaused, completed
    }

    public struct Segment: Equatable {
        public internal(set) var mode: TransportMode
        public let startedAt: Double
        public internal(set) var endedAt: Double?
        public internal(set) var points: [LocationSample]
    }

    public struct Stop: Equatable {
        public let lat: Double
        public let lon: Double
        public let arrivedAt: Double
        public internal(set) var departedAt: Double?

        public init(lat: Double, lon: Double, arrivedAt: Double, departedAt: Double?) {
            self.lat = lat
            self.lon = lon
            self.arrivedAt = arrivedAt
            self.departedAt = departedAt
        }
    }

    public private(set) var state: State = .idle
    public private(set) var segments: [Segment] = []
    public private(set) var stops: [Stop] = []
    public let vehicle: VehicleType

    /// Mode of the segment currently being recorded (S2 HUD).
    public var currentMode: TransportMode? { open?.mode }

    private let config: TrackingConfig
    private var open: Segment?
    private var smoother: SpeedSmoother
    private var dwellDetector: DwellDetector
    private var lastAccepted: LocationSample?
    private struct Fix {
        let ts: Double
        let lat: Double
        let lon: Double
    }

    /// Recent fixes for baseline speed derivation when the OS gives no speed.
    private var recentFixes: [Fix] = []
    private var candidateMode: TransportMode?
    private var candidateSince: Double = 0
    private var candidateLastSeen: Double = 0
    private var pausedStopCenter: (lat: Double, lon: Double)?

    public init(config: TrackingConfig, vehicle: VehicleType) {
        self.config = config
        self.vehicle = vehicle
        smoother = SpeedSmoother(windowS: config.segmentation.speedSmoothingWindowS)
        dwellDetector = DwellDetector(config: config.dwell)
    }

    public func start(at ts: Double) {
        guard state == .idle else { return }
        state = .recording
        open = Segment(mode: .unknown, startedAt: ts, endedAt: nil, points: [])
    }

    public func process(_ sample: LocationSample, activity: MotionActivity? = nil) {
        guard state == .recording || state == .dwellPaused else { return }
        if let hAcc = sample.hAccM, hAcc > config.filter.maxHAccM { return }

        if state == .dwellPaused {
            processWhilePaused(sample)
            return
        }

        // OS speeds are instantaneous (Doppler) and need smoothing; derived
        // speeds are already a window mean — smoothing them twice smears
        // short bursts past the mode-confirm threshold.
        let smoothedKmh: Double
        if let osSpeed = sample.speedMps {
            smoothedKmh = smoother.add(ts: sample.ts, mps: max(0, osSpeed)) * 3.6
        } else {
            smoothedKmh = derivedSpeedMps(for: sample) * 3.6
        }
        lastAccepted = sample
        open?.points.append(sample)

        // Never dwell-pause mid-walk: wandering a temple or night market is a
        // stop, but pausing GPS there would throw away exactly the walking
        // trace the recap wants — StopDeriver turns compact walk segments
        // into stops at trip end instead (ADR 2026-07-18).
        if open?.mode != .walk, let dwell = dwellDetector.add(ts: sample.ts, lat: sample.lat, lon: sample.lon) {
            beginDwell(dwell)
            return
        }
        updateMode(
            candidate: ModeClassifier.classify(
                smoothedKmh: smoothedKmh,
                activity: activity,
                vehicle: vehicle,
                config: config.segmentation
            ),
            at: sample.ts
        )
    }

    public func finish(at ts: Double) {
        guard state == .recording || state == .dwellPaused else { return }
        if state == .dwellPaused, !stops.isEmpty {
            stops[stops.count - 1].departedAt = ts
        }
        closeOpenSegment(at: ts)
        state = .completed
    }

    // MARK: - Dwell

    private func beginDwell(_ dwell: DwellDetector.Dwell) {
        // Points recorded while already standing at the stop belong to the
        // stop, not the segment's polyline.
        open?.points.removeAll { $0.ts > dwell.sinceTs }
        closeOpenSegment(at: dwell.sinceTs)
        stops.append(Stop(lat: dwell.centerLat, lon: dwell.centerLon, arrivedAt: dwell.sinceTs, departedAt: nil))
        pausedStopCenter = (dwell.centerLat, dwell.centerLon)
        state = .dwellPaused
        resetTransientState()
    }

    private func processWhilePaused(_ sample: LocationSample) {
        guard let center = pausedStopCenter else { return }
        let distance = Geo.distanceM(latA: sample.lat, lonA: sample.lon, latB: center.lat, lonB: center.lon)
        // Mirrors the CLMonitor region-exit resume (§2.3): inside the region
        // the GPS would be off, so points are ignored.
        guard distance > config.dwell.regionRadiusM else { return }
        if !stops.isEmpty {
            stops[stops.count - 1].departedAt = sample.ts
        }
        pausedStopCenter = nil
        state = .recording
        open = Segment(mode: .unknown, startedAt: sample.ts, endedAt: nil, points: [sample])
        lastAccepted = sample
    }

    // MARK: - Mode confirmation (§4.1)

    private func updateMode(candidate: TransportMode?, at ts: Double) {
        guard let candidate else {
            // No evidence (stationary or inconclusive band): freeze — noisy
            // speeds dip in and out of evidence, and a walker at 5 km/h must
            // still accumulate their 60 s of walk. Only contradicting
            // evidence or staleness clears a candidate.
            return
        }
        guard candidate != open?.mode else {
            candidateMode = nil
            return
        }
        let confirmS = config.segmentation.modeConfirmS
        if candidateMode != candidate || ts - candidateLastSeen > confirmS {
            // New candidate, or the old one went stale (two isolated speed
            // spikes minutes apart must not add up to a confirmation).
            candidateMode = candidate
            candidateSince = ts
            candidateLastSeen = ts
            return
        }
        candidateLastSeen = ts
        guard ts - candidateSince >= confirmS else { return }

        if open?.mode == .unknown {
            // First confident classification adopts the open segment instead
            // of splitting off a stub.
            open?.mode = candidate
        } else {
            splitOpenSegment(at: candidateSince, newMode: candidate)
        }
        candidateMode = nil
    }

    private func splitOpenSegment(at ts: Double, newMode: TransportMode) {
        guard var closing = open else { return }
        let carried = closing.points.filter { $0.ts >= ts }
        closing.points.removeAll { $0.ts >= ts }
        closing.endedAt = ts
        appendIfMeaningful(closing)
        open = Segment(mode: newMode, startedAt: ts, endedAt: nil, points: carried)
    }

    private func closeOpenSegment(at ts: Double) {
        guard var closing = open else { return }
        closing.endedAt = ts
        appendIfMeaningful(closing)
        open = nil
    }

    private func appendIfMeaningful(_ segment: Segment) {
        // A polyline needs two points; anything less is a stub between states.
        guard segment.points.count >= 2 else { return }
        segments.append(segment)
    }

    private func resetTransientState() {
        smoother.reset()
        dwellDetector.reset()
        candidateMode = nil
        lastAccepted = nil
        recentFixes.removeAll()
        open = nil
    }

    /// Displacement over the smoothing window, not between consecutive fixes:
    /// per-fix GPS noise (±10–15 m in cities) makes adjacent-point speeds
    /// useless — a stroller measures as a cyclist.
    private func derivedSpeedMps(for sample: LocationSample) -> Double {
        recentFixes.append(Fix(ts: sample.ts, lat: sample.lat, lon: sample.lon))
        let windowS = config.segmentation.speedSmoothingWindowS
        recentFixes.removeAll { $0.ts < sample.ts - windowS }
        guard let oldest = recentFixes.first, sample.ts - oldest.ts >= windowS / 3 else { return 0 }
        let meters = Geo.distanceM(latA: oldest.lat, lonA: oldest.lon, latB: sample.lat, lonB: sample.lon)
        return meters / (sample.ts - oldest.ts)
    }
}

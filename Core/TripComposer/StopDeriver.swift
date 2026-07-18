import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// Trip-end stop derivation (ADR 2026-07-18): the live dwell detector only
/// sees stops where the phone is stationary *and* still producing fixes. The
/// 2026-07-18 drive missed both real stops two other ways:
///
/// - **Silence stop (the 7-11):** a parked phone stops getting location
///   callbacks under a distance filter, so 10 minutes vanished into a sample
///   gap inside the drive segment. Detectable retroactively: a gap of at
///   least `dwell.gap_min_s` whose displacement stays within
///   `dwell.radius_m`.
/// - **Walk visit (the temple):** park, wander the grounds for 20 minutes.
///   The engine correctly records a walk segment and deliberately never
///   dwell-pauses during it (the walking trace is recap material) — so a
///   walk segment bracketed by vehicle segments *is* the stop when it lasts
///   at least `dwell.visit_min_s` and closes its loop (ends within
///   `dwell.visit_return_radius_m` of where it began). Loop closure, not
///   wander extent, separates a visit from an A→B walk: trailhead loops
///   range hundreds of meters and still end back at the car. A walk at the
///   trip's final destination derives nothing — you never drove away, so
///   that's the trip's end, not a stop.
///
/// Derived stops never duplicate engine stops: any overlap in time defers to
/// the live detector's row.
public enum StopDeriver {
    public static func derive(
        segments: [TrackingEngine.Segment],
        engineStops: [TrackingEngine.Stop],
        config: TrackingConfig
    ) -> [TrackingEngine.Stop] {
        var derived: [TrackingEngine.Stop] = []
        derived += silenceStops(segments: segments, config: config.dwell)
        derived += walkVisitStops(segments: segments, config: config.dwell)

        let taken = engineStops.map { ($0.arrivedAt, $0.departedAt ?? .greatestFiniteMagnitude) }
        var kept: [TrackingEngine.Stop] = []
        for stop in derived.sorted(by: { $0.arrivedAt < $1.arrivedAt }) {
            let end = stop.departedAt ?? .greatestFiniteMagnitude
            let overlapsEngine = taken.contains { stop.arrivedAt < $0.1 && $0.0 < end }
            let overlapsKept = kept.contains {
                stop.arrivedAt < ($0.departedAt ?? .greatestFiniteMagnitude) && $0.arrivedAt < end
            }
            if !overlapsEngine && !overlapsKept {
                kept.append(stop)
            }
        }
        return kept
    }

    private static func silenceStops(
        segments: [TrackingEngine.Segment],
        config: TrackingConfig.Dwell
    ) -> [TrackingEngine.Stop] {
        var stops: [TrackingEngine.Stop] = []
        for segment in segments {
            var previous: LocationSample?
            for point in segment.points {
                if let previous,
                   point.ts - previous.ts >= config.gapMinS,
                   Geo.distanceM(latA: previous.lat, lonA: previous.lon, latB: point.lat, lonB: point.lon) <= config.radiusM {
                    stops.append(TrackingEngine.Stop(
                        lat: previous.lat, lon: previous.lon,
                        arrivedAt: previous.ts, departedAt: point.ts
                    ))
                }
                previous = point
            }
        }
        return stops
    }

    private static func walkVisitStops(
        segments: [TrackingEngine.Segment],
        config: TrackingConfig.Dwell
    ) -> [TrackingEngine.Stop] {
        var stops: [TrackingEngine.Stop] = []
        for (index, segment) in segments.enumerated() {
            guard segment.mode == .walk,
                  index > 0, isVehicle(segments[index - 1].mode),
                  index + 1 < segments.count, isVehicle(segments[index + 1].mode),
                  let first = segment.points.first, let last = segment.points.last
            else { continue }
            let endedAt = segment.endedAt ?? last.ts
            guard endedAt - segment.startedAt >= config.visitMinS else { continue }
            let closure = Geo.distanceM(latA: first.lat, lonA: first.lon, latB: last.lat, lonB: last.lon)
            guard closure <= config.visitReturnRadiusM else { continue }
            // Pin the stop where the walk began — that's where the car is.
            stops.append(TrackingEngine.Stop(
                lat: first.lat, lon: first.lon,
                arrivedAt: segment.startedAt, departedAt: endedAt
            ))
        }
        return stops
    }

    private static func isVehicle(_ mode: TransportMode) -> Bool {
        switch mode {
        case .drive, .scooter, .cycle, .transit: return true
        case .walk, .unknown: return false
        }
    }
}

import KamomePersistence
import KamomeTrackingEngine

// Outside `TrackingSession.swift`, which is at SwiftLint's length limit.
extension TripRepository.NewSegment {
    /// A recorded segment as `TrackingSession` stores it on End Trip.
    init(recorded segment: TrackingEngine.Segment) {
        self.init(
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
}

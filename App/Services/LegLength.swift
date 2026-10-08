import Foundation
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer

/// **How long a leg was**, measured once for every screen that prints it — the
/// diary's connectors and the Discovery timeline's kilometres read this, so
/// the two cannot disagree about one trip.
enum LegLength {
    /// Along the road when one was matched, else along the raw points — the
    /// same choice the film makes (`RecapComposer.legs`).
    static func meters(segment: SegmentRecord, points: [TrackpointRecord]) -> Double {
        let coordinates: [(lat: Double, lon: Double)]
        if let encoded = segment.matchedPolyline, case let decoded = EncodedPolyline.decode(encoded), decoded.count >= 2 {
            coordinates = decoded.map { ($0.lat, $0.lon) }
        } else {
            coordinates = points.map { ($0.lat, $0.lon) }
        }
        return zip(coordinates, coordinates.dropFirst()).reduce(0.0) { sum, pair in
            sum + Geo.distanceM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
        }
    }

    /// **Kilometres on the ground** (Chiu, 2026-09-23: 「只算地面交通（開車、步行、火車）」).
    ///
    /// A flight is not a road trip, and a timeline line reading "1,240 km"
    /// where 1,000 of it was a plane says the user drove far. So a leg counts
    /// only when its mode is a ground mode **and** routing has answered that a
    /// road joins its ends (`road`, or `implausibleRoute` — a road exists, the
    /// route was refused, so it is measured along the points). A leg routing has
    /// not answered for is left out: it may be a crossing, and an undercount
    /// that fills in when routing lands is honest where an overcount is not.
    ///
    /// nil when no leg qualifies — the timeline then prints no distance at all
    /// rather than "0 km".
    static func groundMeters(_ segments: [(segment: SegmentRecord, points: [TrackpointRecord])]) -> Double? {
        let ground = segments.filter { item in
            guard let mode = TransportMode(rawValue: item.segment.mode), groundModes.contains(mode) else { return false }
            switch item.segment.routeVerdict {
            case .road, .implausibleRoute: return true
            // Off the road network (ADR 2026-09-23 (c)) is mostly a beach, but
            // a window-seat photograph reads the same, and that leg is a
            // flight. Left out on the same rule as an unanswered leg.
            case .noRoad, .offRoadNetwork, .beyondDriving, nil: return false
            }
        }
        guard !ground.isEmpty else { return nil }
        return ground.reduce(0.0) { $0 + meters(segment: $1.segment, points: $1.points) }
    }

    /// **A stored trip's kilometres on the ground** — the one figure Home,
    /// Footprints and Trip Detail's stat card print for it (2026-10-07: the
    /// same trip read 271 km on Home and no distance at all in Footprints;
    /// #242 brought Trip Detail in). A recording's own stats are its measured
    /// distance; a trip rebuilt from photographs is measured along its routed
    /// legs, flights left out, by the rule above.
    static func groundMeters(trip: TripRecord, repository: TripRepository) -> Double? {
        if let measured = recordedMeters(trip) { return measured }
        guard let detail = Stored.read("detail", { try repository.detail(tripId: trip.id) }) else { return nil }
        return groundMeters(trip: trip, segments: detail.segments)
    }

    /// The same figure, for a caller that already holds the trip's legs.
    static func groundMeters(trip: TripRecord, segments: [(segment: SegmentRecord, points: [TrackpointRecord])]) -> Double? {
        recordedMeters(trip) ?? groundMeters(segments)
    }

    /// A recording's measured distance; nil for a trip rebuilt from photographs.
    private static func recordedMeters(_ trip: TripRecord) -> Double? {
        guard !trip.tripSource.isReconstructed else { return nil }
        return TripStats.from(jsonString: trip.statsJson)?.distanceM
    }

    /// Everything that moves over land. `unknown` is not ground: it is what a
    /// leg is called before anyone knows how it was travelled.
    static let groundModes: Set<TransportMode> = [.drive, .scooter, .walk, .cycle, .transit]
}

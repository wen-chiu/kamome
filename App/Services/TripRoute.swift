import Foundation
import KamomePersistence

/// **A trip rebuilt from photographs draws only the route between its stops**
/// (Chiu, 2026-10-30): 「只要有目的地的路徑」.
///
/// An import stores its legs apart from its stops (`PhotoImportClusterer`), so
/// deleting a stop leaves the legs that led to it. Deleting the transit
/// airport a trip began at left a flight from it drawn across the map, and in
/// the film, into the first stop the person kept. A leg is drawn only when it
/// runs between the first stop and the last: before the first or after the
/// last it leads from, or to, a place the trip no longer has. A loose
/// photograph before the first stop goes the same way, for the same reason.
///
/// Read, not deleted: the legs stay stored, so the rule can change without
/// losing anything. A recording keeps every leg — it begins where the person
/// set off, a place it watched them leave (INFERRED that Chiu wants recordings
/// left alone; he named only the import). Fewer than two stops keeps every leg
/// too: no stretch lies between them, and the film must still have a line.
enum TripRoute {
    typealias Leg = (segment: SegmentRecord, points: [TrackpointRecord])

    /// `stops` in arrival order, as `TripRepository.detail` reads them.
    static func legs(trip: TripRecord, segments: [Leg], stops: [StopRecord]) -> [Leg] {
        guard trip.tripSource == .importedPhotos,
              stops.count >= 2, let first = stops.first, let last = stops.last
        else { return segments }
        // An import's leg starts at a stop's departure and ends at the next
        // stop's arrival, both stored from the same photograph's time.
        let leftLast = last.departedAt ?? last.arrivedAt
        return segments.filter { item in
            item.segment.startedAt >= first.arrivedAt
                && (item.segment.endedAt ?? item.segment.startedAt) <= leftLast
        }
    }
}

extension TripRepository.TripDetail {
    /// The legs this trip draws: on its map, in its film, in its distance.
    var routeSegments: [TripRoute.Leg] { TripRoute.legs(trip: trip, segments: segments, stops: stops) }
}

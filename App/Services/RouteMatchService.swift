import Foundation
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine

/// Runs §4.4 road reconstruction over a stored trip: every road-mode segment
/// that has no `matched_polyline` yet is sent to the provider its data suits and
/// the result persisted. Best-effort by construction — failures leave raw
/// geometry in place and are never surfaced to the user (§4.4: never block trip
/// completion or recap on matching). What the user *does* see is honesty: an
/// unreconstructed leg renders inferred in the film (PD-2), never as a confident
/// road.
///
/// **Two providers, dispatched on how the geometry was captured**
/// (typed-leg pass 2026-07-26). A recorded segment is a dense GPS trace and
/// belongs in `/match`, whose Hidden-Markov model expects exactly that. An
/// imported segment is three or four EXIF positions hours apart; `/match` either
/// rejects it or snaps it somewhere arbitrary, so it goes to `/route` with the
/// photo positions as via-waypoints (PD-3). Same storage, same fallback.
struct RouteMatchService {
    private let repository: TripRepository
    private let matcher: RouteMatchProviding
    private let reconstructor: RouteReconstructing

    init(
        repository: TripRepository,
        config: TrackingConfig,
        provider: RouteMatchProviding? = nil,
        reconstructor: RouteReconstructing? = nil
    ) {
        self.repository = repository
        matcher = provider ?? OSRMMatchProvider(config: config.matching)
        self.reconstructor = reconstructor ?? OSRMRouteProvider(config: config.matching)
    }

    /// Idempotent: already-matched segments are skipped, so every caller
    /// (trip end, import, recap export) can fire it freely.
    func matchTrip(tripId: String) async {
        guard let detail = try? repository.detail(tripId: tripId) else { return }
        for item in detail.segments where shouldReconstruct(item.segment, points: item.points) {
            let trace = item.points.map {
                RouteMatchPoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAccM: $0.hAcc)
            }
            let outcome: RouteMatchOutcome?
            switch item.segment.segmentSource {
            case .exif, .timeline:
                outcome = (try? await reconstructor.route(trace)) ?? nil
            case .gpsHifi, .gpsPassive:
                outcome = (try? await matcher.match(trace)) ?? nil
            }
            guard let outcome else { continue }
            try? repository.setMatchedPolyline(
                segmentId: item.segment.id,
                encodedPolyline: outcome.encodedPolyline
            )
        }
    }

    private func shouldReconstruct(_ segment: SegmentRecord, points: [TrackpointRecord]) -> Bool {
        guard segment.matchedPolyline == nil, points.count >= 2 else { return false }
        // The self-hosted server runs the car profile: drive and scooter follow
        // the drivable network. Walks stay raw — feet ignore roads, and snapping
        // a stroll to the nearest street invents a journey (PD-8). Cycle,
        // transit and unknown stay raw for the same reason.
        switch TransportMode(rawValue: segment.mode) {
        case .drive, .scooter: return true
        default: return false
        }
    }
}

import Foundation
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine

/// Runs §4.4 map matching over a stored trip: every road-mode segment that
/// has no `matched_polyline` yet is sent to the provider and the confident
/// result persisted. Best-effort by construction — failures leave raw
/// geometry in place and are never surfaced to the user (§4.4: never block
/// trip completion or recap on matching).
struct RouteMatchService {
    private let repository: TripRepository
    private let provider: RouteMatchProviding

    init(repository: TripRepository, config: TrackingConfig, provider: RouteMatchProviding? = nil) {
        self.repository = repository
        self.provider = provider ?? OSRMMatchProvider(config: config.matching)
    }

    /// Idempotent: already-matched segments are skipped, so both callers
    /// (trip end, recap export) can fire it freely.
    func matchTrip(tripId: String) async {
        guard let detail = try? repository.detail(tripId: tripId) else { return }
        for item in detail.segments where shouldMatch(item.segment, points: item.points) {
            let trace = item.points.map {
                RouteMatchPoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAccM: $0.hAcc)
            }
            guard let outcome = (try? await provider.match(trace)) ?? nil else { continue }
            try? repository.setMatchedPolyline(
                segmentId: item.segment.id,
                encodedPolyline: outcome.encodedPolyline
            )
        }
    }

    private func shouldMatch(_ segment: SegmentRecord, points: [TrackpointRecord]) -> Bool {
        guard segment.matchedPolyline == nil, points.count >= 2 else { return false }
        // The self-hosted server runs the car profile: drive and scooter
        // follow the drivable network. Walks stay raw (feet ignore roads;
        // a foot profile is a future provider), as do cycle/transit/unknown.
        switch TransportMode(rawValue: segment.mode) {
        case .drive, .scooter: return true
        default: return false
        }
    }
}

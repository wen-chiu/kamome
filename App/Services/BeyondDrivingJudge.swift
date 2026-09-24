import Foundation
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching

/// Whether a stored leg is **too fast to have been driven**, storing the verdict
/// when it is (ADR 2026-09-24 (f)). `RouteMatchService` asks this before it asks
/// routing, and a leg it answers `true` for is never sent.
///
/// Its own file because the rule is `LegPace`'s physics plus the storage policy
/// around it, and `RouteMatchService` is at its length budget.
enum BeyondDrivingJudge {
    /// Only legs nobody watched being travelled: a recorded trace is the road the
    /// phone saw, never a pace between two photos. A stored `road` keeps its
    /// geometry and `noRoad` is already a crossing, so neither is judged.
    /// `implausibleRoute` and `offRoadNetwork` **are** overwritten: both were
    /// learnt by asking a road router about a leg nobody drove, which is the
    /// question this verdict says should never have been asked — the Vietnam
    /// film's opening leg may be stored as either (`Docs/handoff-vietnam-crossing.md`).
    ///
    /// ⚠️ Like every stored verdict it is not re-judged if the tunables change:
    /// `setRoutability` never writes NULL, so a leg once judged stays judged.
    static func judge(
        _ segment: SegmentRecord,
        points: [TrackpointRecord],
        config: TrackingConfig.Matching,
        repository: TripRepository
    ) -> Bool {
        switch segment.segmentSource {
        case .exif, .timeline, .mergeGap: break
        case .gpsHifi, .gpsPassive: return false
        }
        switch segment.routeVerdict {
        case .beyondDriving?: return true
        case .road?, .noRoad?: return false
        case .implausibleRoute?, .offRoadNetwork?, nil: break
        }
        guard segment.matchedPolyline == nil, let first = points.first, let last = points.last,
              points.count >= 2 else { return false }
        let beyond = LegPace.isBeyondDriving(
            from: RouteMatchPoint(ts: first.ts, lat: first.lat, lon: first.lon),
            to: RouteMatchPoint(ts: last.ts, lat: last.lat, lon: last.lon),
            config: config
        )
        if beyond {
            Stored.write("setRoutability") { try repository.setRoutability(segmentId: segment.id, .beyondDriving) }
        }
        return beyond
    }
}

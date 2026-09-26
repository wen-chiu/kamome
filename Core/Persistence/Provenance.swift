import Foundation

/// Honest provenance (spec §3; `decisions.md` 2026-07-20 Replay MVP
/// repositioning). What actually produced a trip — load-bearing, not
/// cosmetic: the UI must distinguish a real recording from one reconstructed
/// from photo locations, and must never present an import as a "Verified Trip".
/// Raw values are the on-disk `trip.source` strings.
public enum TripSource: String, CaseIterable, Sendable {
    /// Kamome actually recorded this trip's GPS (high-fidelity or passive).
    case recorded
    /// Reconstructed from photo EXIF place + time — the Replay MVP importer.
    case importedPhotos = "imported_photos"
    /// Reserved forward-compat only: no Google Timeline importer is planned
    /// (dropped as redundant, `decisions.md` 2026-07-20).
    case importedTimeline = "imported_timeline"

    /// True when the route is inferred from sparse data rather than recorded.
    /// Drives the "reconstructed from photos" labeling and inferred-leg
    /// rendering (spec §5/§6). Never claim a reconstructed trip as proof.
    public var isReconstructed: Bool { self != .recorded }

    /// Legacy/unknown strings read as `recorded` — the schema-v1 default and
    /// the safe assumption for rows written before v2.
    public init(storage: String?) {
        self = storage.flatMap(TripSource.init(rawValue:)) ?? .recorded
    }
}

/// How a single segment's geometry was obtained. Raw values are the on-disk
/// `segment.source` strings; the column is nullable and NULL reads as
/// `gpsHifi` (legacy rows predate the concept).
public enum SegmentSource: String, CaseIterable, Sendable {
    /// Continuous adaptive GPS — the Phase 1 high-fidelity engine.
    case gpsHifi = "gps_hifi"
    /// Sparse significant-location-change fixes — passive capture (Capture Beta).
    case gpsPassive = "gps_passive"
    /// Reserved forward-compat only (no Timeline importer planned).
    case timeline
    /// Points reconstructed from photo EXIF — the Replay MVP importer.
    case exif
    /// The stretch between two merged trips that ended and began far apart
    /// (ADR 2026-09-24 (b)): two points, the end of one and the start of the next,
    /// and nothing observed in between. Treated as `exif` is — routed, and
    /// dashed when no road comes back — never as a recording.
    case mergeGap = "merge_gap"

    /// NULL / unknown reads as `gpsHifi` (schema-v1 behavior).
    public init(storage: String?) {
        self = storage.flatMap(SegmentSource.init(rawValue:)) ?? .gpsHifi
    }
}

/// **What routing established about whether a road joins a segment's ends**
/// (schema v4, 2026-08-30). Raw values are the on-disk `segment.routability`
/// strings; the column is nullable and **NULL means nothing was established**.
///
/// Stored rather than derived, for the reason `stop.kind` and `segment.source`
/// are: it is a fact about the journey, learnt once, by a step that no longer
/// runs anywhere near the export. Routing was detached from import on
/// 2026-08-15 and runs in the background; a recap may be rendered days later,
/// after a relaunch, and cannot re-ask. The alternative — carrying the verdict
/// in `RouteMatchReport` — dies with the run that produced it.
///
/// **NULL must never be read as `noRoad`.** Routing ships disabled
/// (`matching.base_url` empty), and every leg of every trip imported before this
/// column existed is NULL. Treating that as "there is no road here" would fly a
/// sprite over every motorway in the library — which is exactly the collapse
/// this enum exists to prevent (`RouteReconstruction`).
public enum SegmentRoutability: String, CaseIterable, Sendable {
    /// A road route came back and is stored in `matched_polyline`.
    case road
    /// The provider answered and there is **no road** joining these places.
    /// One of the two verdicts a crossing is built on — the other is
    /// `beyondDriving` (ADR 2026-09-24 (f))
    /// (`Docs/camera-arcs.md` §0).
    case noRoad = "no_road"
    /// A road route came back and the PD-3 detour gate refused it. A road
    /// exists; this route is not trustworthy. Dashed, never flown.
    case implausibleRoute = "implausible_route"
    /// The provider answered and a waypoint has **no road anywhere near it** —
    /// a beach, a cape, a trail (ADR 2026-09-23 (c)). A fact about the ground,
    /// so it is stored and never re-asked; **not a crossing**, so no plane and
    /// no arc. Before v7 these were stored as `no_road`, and v7 clears those
    /// rows so each is asked once more and lands in the right one of the two.
    /// Since v11 it also holds land a car cannot reach but a walk can, with no
    /// ferry (ADR 2026-09-25 (c)); v11 cleared `no_road` a second time for it.
    case offRoadNetwork = "off_road_network"
    /// **Nobody drove this** (ADR 2026-09-24 (f)): the straight line between the
    /// leg's ends was covered faster than any drive averages, even with the
    /// clocks given every benefit of the doubt (`LegPace`). Judged on the phone,
    /// never asked of routing, and **a crossing** — the plane flies it. Kept apart
    /// from `noRoad` because it is a different fact: we know it was not driven,
    /// not that no road exists.
    case beyondDriving = "beyond_driving"

    /// NULL / unknown stays **nil** rather than defaulting, unlike its two
    /// sibling enums. Both of those have a safe legacy meaning ("this was a
    /// recording"); this one does not — "we never found out" is a third state
    /// and collapsing it into either answer is a claim about the ground.
    public init?(storage: String?) {
        guard let storage, let value = SegmentRoutability(rawValue: storage) else { return nil }
        self = value
    }

    // MARK: - Which rules a verdict was reached under (schema v13)

    /// **Bump this when a rule that produces a verdict changes**, and raise that
    /// verdict's `lastRevised` to the new number (arch review 2026-09-26, round
    /// 2 point 3). Until this existed, a stored verdict was never re-asked, so
    /// v7 and v11 each had to clear `no_road` with a data migration, and ADR
    /// 2026-09-24 (f) had to accept that retuning the pace numbers would not
    /// touch a leg already judged. Now a rule change re-asks exactly the legs
    /// whose verdict it could change, and no others — a `road` stays road.
    public static let rulesVersion = 2

    /// The rules version in which this verdict's rule last changed.
    ///
    /// - 1: everything up to and including ADR 2026-09-25 (c); v7 and v11
    ///   already brought stored rows up to it.
    /// - 2: `crossing_pace_min_kmh` 150 → 160 (ADR 2026-09-26 (b)). Only
    ///   `beyondDriving` can change under it — a raised threshold makes a leg
    ///   judged at 150–160 km/h no longer a crossing, and makes nothing else
    ///   one — so only those legs are judged again (on the phone, and sent to
    ///   routing only if they are no longer too fast).
    public var lastRevised: Int {
        switch self {
        case .road, .noRoad, .implausibleRoute, .offRoadNetwork: return 1
        case .beyondDriving: return 2
        }
    }

    /// Whether a verdict stored under `version` (NULL = 1) is still an answer.
    public func stillHolds(storedUnder version: Int?, lastRevised: Int? = nil) -> Bool {
        (version ?? 1) >= (lastRevised ?? self.lastRevised)
    }
}

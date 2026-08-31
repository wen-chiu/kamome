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
    /// The only verdict the cross-region crossing beat may be built on
    /// (`Docs/camera-arcs.md` §0).
    case noRoad = "no_road"
    /// A road route came back and the PD-3 detour gate refused it. A road
    /// exists; this route is not trustworthy. Dashed, never flown.
    case implausibleRoute = "implausible_route"

    /// NULL / unknown stays **nil** rather than defaulting, unlike its two
    /// sibling enums. Both of those have a safe legacy meaning ("this was a
    /// recording"); this one does not — "we never found out" is a third state
    /// and collapsing it into either answer is a claim about the ground.
    public init?(storage: String?) {
        guard let storage, let value = SegmentRoutability(rawValue: storage) else { return nil }
        self = value
    }
}

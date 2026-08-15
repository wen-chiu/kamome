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

import Foundation
import GRDB

/// What on-device Vision found in one photograph (schema v11, ADR 2026-09-25
/// (c)). Keyed by **asset**, not by trip: a photograph re-matched, merged into
/// another trip or imported twice is analysed once. Derived from pixels that
/// never leave the device, and it never leaves the device either (§0).
public struct PhotoAnalysisRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "photo_analysis"

    /// How far the analysis got.
    public enum Outcome: String, Codable, Sendable {
        /// Vision saw the pixels.
        case analyzed
        /// The pixels were not on the device (or the asset is gone). The row
        /// still counts as done — a trip is never held on the old pick by one
        /// photograph in iCloud — and plays as a photograph with no signal.
        case unavailable
    }

    public var phAssetId: String
    /// The analyser's own version; a row from an older one is analysed again.
    public var version: Int
    public var outcome: Outcome
    /// 1 — a screenshot, receipt or document. NULL — not known.
    public var isUtility: Int?
    /// Vision's aesthetics score, −1…1. NULL before iOS 18 or without pixels.
    public var quality: Double?
    /// The feature print as little-endian Float32s. NULL without pixels.
    public var featurePrint: Data?
    public var analyzedAt: Double

    enum CodingKeys: String, CodingKey {
        case version, outcome, quality
        case phAssetId = "ph_asset_id"
        case isUtility = "is_utility"
        case featurePrint = "feature_print"
        case analyzedAt = "analyzed_at"
    }

    public init(
        phAssetId: String, version: Int, outcome: Outcome, isUtility: Int? = nil,
        quality: Double? = nil, featurePrint: Data? = nil, analyzedAt: Double
    ) {
        self.phAssetId = phAssetId
        self.version = version
        self.outcome = outcome
        self.isUtility = isUtility
        self.quality = quality
        self.featurePrint = featurePrint
        self.analyzedAt = analyzedAt
    }

    /// The feature print as floats — the inverse of `encode(featurePrint:)`.
    public var featurePrintFloats: [Float]? {
        guard let featurePrint, featurePrint.count % MemoryLayout<UInt32>.size == 0, !featurePrint.isEmpty
        else { return nil }
        return featurePrint.withUnsafeBytes { raw in
            (0..<raw.count / 4).map {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
            }
        }
    }

    /// Floats as little-endian bytes, whatever the host's byte order.
    public static func encode(featurePrint floats: [Float]) -> Data {
        var data = Data(capacity: floats.count * 4)
        for value in floats {
            let bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: bits) { data.append(contentsOf: $0) }
        }
        return data
    }
}

extension TripRepository {
    // MARK: - Photo analysis (schema v11)

    /// The trip's photographs at a stop that still need Vision: never
    /// analysed, analysed by an older version, or unavailable last time (a
    /// cloud-only photograph may be on the device now). Time order, so a run
    /// cut short has done the start of the trip.
    public func assetsNeedingAnalysis(tripId: String, version: Int) throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT p.ph_asset_id FROM photo_ref p
                LEFT JOIN photo_analysis a ON a.ph_asset_id = p.ph_asset_id
                WHERE p.trip_id = ? AND p.stop_id IS NOT NULL
                  AND (a.ph_asset_id IS NULL OR a.version < ? OR a.outcome = 'unavailable')
                ORDER BY p.taken_at, p.ph_asset_id
                """, arguments: [tripId, version])
        }
    }

    public func savePhotoAnalysis(_ record: PhotoAnalysisRecord) throws {
        try database.writer.write { db in try record.save(db) }
    }

    /// Every analysis row for a trip's photographs, by asset.
    public func photoAnalyses(tripId: String) throws -> [String: PhotoAnalysisRecord] {
        try database.writer.read { db in try Self.photoAnalyses(db, tripId: tripId) }
    }

    static func photoAnalyses(_ db: Database, tripId: String) throws -> [String: PhotoAnalysisRecord] {
        let rows = try PhotoAnalysisRecord.fetchAll(db, sql: """
            SELECT * FROM photo_analysis
            WHERE ph_asset_id IN (SELECT ph_asset_id FROM photo_ref WHERE trip_id = ?)
            """, arguments: [tripId])
        return Dictionary(rows.map { ($0.phAssetId, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

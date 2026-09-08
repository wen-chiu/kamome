import Foundation
import GRDB

/// A finished recap film stored inside the app (schema v5, Phase 4 closeout).
///
/// The record persists what was previously recoverable only from a log line:
/// appearance, mode, render time, and the path to the file on disk. The path
/// is **relative** — resolved against the app container at read time — because
/// the container UUID changes across app updates and restores, and a stored
/// absolute URL silently stops resolving.
///
/// One trip can own many films (re-exports, format variants). Deleting a trip
/// must delete its film rows **and** their files — an orphaned 56 MB file is
/// the failure mode the cascade prevents.
public struct FilmRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "film"

    public var id: String
    public var tripId: String
    /// Path relative to the app's Application Support directory.
    /// Resolved at read time; never stored as an absolute URL.
    public var relativePath: String
    /// `mp4` or `gif`.
    public var format: String
    public var createdAt: Double
    /// Film duration in seconds (from the timeline, not wall-clock render time).
    public var durationS: Double?
    /// Wall-clock seconds the render took — the §4.5 render-budget readout.
    public var renderSeconds: Double?
    /// `light` or `dark` — the appearance captured at the composition boundary
    /// (ADR 2026-08-15). This is where the gap that comment named is closed.
    public var appearance: String
    /// `highlight` or `full`.
    public var recapMode: String
    /// On-disk size in bytes, for the trip-detail display.
    public var fileBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case id, format, appearance
        case tripId = "trip_id"
        case relativePath = "relative_path"
        case createdAt = "created_at"
        case durationS = "duration_s"
        case renderSeconds = "render_seconds"
        case recapMode = "recap_mode"
        case fileBytes = "file_bytes"
    }

    public init(
        id: String,
        tripId: String,
        relativePath: String,
        format: String,
        createdAt: Double,
        durationS: Double? = nil,
        renderSeconds: Double? = nil,
        appearance: String,
        recapMode: String,
        fileBytes: Int64? = nil
    ) {
        self.id = id
        self.tripId = tripId
        self.relativePath = relativePath
        self.format = format
        self.createdAt = createdAt
        self.durationS = durationS
        self.renderSeconds = renderSeconds
        self.appearance = appearance
        self.recapMode = recapMode
        self.fileBytes = fileBytes
    }
}

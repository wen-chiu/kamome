import Foundation
import GRDB

/// Photo-EXIF import write path (spec §4.7), split out so `TripRepository`
/// stays within its size budget. Imports become ordinary trips that flow
/// through Trip Detail / RecapComposer / ExportEngine unchanged; the only
/// difference is honest provenance (`trip.source` / `segment.source`, §3).
public extension TripRepository {
    /// A photo to persist as a `photo_ref` (schema §3). Referenced by PhotoKit
    /// identifier only — image bytes are never copied.
    struct NewPhoto {
        public let assetId: String
        public let takenAt: Double?
        public let lat: Double?
        public let lon: Double?
        public let isHighlight: Bool

        public init(assetId: String, takenAt: Double? = nil, lat: Double? = nil,
                    lon: Double? = nil, isHighlight: Bool = false) {
            self.assetId = assetId
            self.takenAt = takenAt
            self.lat = lat
            self.lon = lon
            self.isHighlight = isHighlight
        }
    }

    /// A stop plus the photos taken there — the importer attaches photos to
    /// stops by construction (§4.7), so they are saved together.
    struct NewStopWithPhotos {
        public let stop: NewStop
        public let photos: [NewPhoto]

        public init(stop: NewStop, photos: [NewPhoto]) {
            self.stop = stop
            self.photos = photos
        }
    }

    /// Everything needed to persist one imported trip.
    struct ImportedTrip {
        public let title: String
        public let startedAt: Double
        public let endedAt: Double
        /// `TripSource` raw value — the importer sets `imported_photos`.
        public let source: String
        public let segments: [NewSegment]
        public let stopsWithPhotos: [NewStopWithPhotos]
        /// Photos whose cluster fell below the stop threshold (`stop_id = NULL`).
        public let routeAttachedPhotos: [NewPhoto]

        public init(title: String, startedAt: Double, endedAt: Double, source: String,
                    segments: [NewSegment], stopsWithPhotos: [NewStopWithPhotos],
                    routeAttachedPhotos: [NewPhoto]) {
            self.title = title
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.source = source
            self.segments = segments
            self.stopsWithPhotos = stopsWithPhotos
            self.routeAttachedPhotos = routeAttachedPhotos
        }
    }

    /// Persists a reconstructed-from-photos trip atomically and returns its id.
    /// OSRM snapping (§4.4) runs afterward, best-effort — never here.
    @discardableResult
    func saveImportedTrip(_ trip: ImportedTrip) throws -> String {
        let tripId = UUID().uuidString
        try database.writer.write { db in
            try TripRecord(
                id: tripId, title: trip.title,
                startedAt: trip.startedAt, endedAt: trip.endedAt,
                status: "completed", source: trip.source
            ).insert(db)

            for segment in trip.segments {
                try insertSegment(segment, tripId: tripId, into: db)
            }
            for group in trip.stopsWithPhotos {
                let stopId = UUID().uuidString
                try StopRecord(
                    id: stopId, tripId: tripId,
                    lat: group.stop.lat, lon: group.stop.lon,
                    arrivedAt: group.stop.arrivedAt, departedAt: group.stop.departedAt,
                    kind: group.stop.kind
                ).insert(db)
                for photo in group.photos {
                    try insertPhoto(photo, tripId: tripId, stopId: stopId, into: db)
                }
            }
            for photo in trip.routeAttachedPhotos {
                try insertPhoto(photo, tripId: tripId, stopId: nil, into: db)
            }
        }
        return tripId
    }

    private func insertSegment(_ segment: NewSegment, tripId: String, into db: Database) throws {
        let segmentId = UUID().uuidString
        try SegmentRecord(
            id: segmentId, tripId: tripId, mode: segment.mode,
            startedAt: segment.startedAt, endedAt: segment.endedAt, source: segment.source
        ).insert(db)
        let points = segment.points.map { point in
            TrackpointRecord(
                segmentId: segmentId, ts: point.ts, lat: point.lat, lon: point.lon,
                hAcc: point.hAcc, speed: point.speed, course: point.course, altitude: point.altitude
            )
        }
        try TrackpointRecord.bulkInsert(points, into: db)
    }

    private func insertPhoto(_ photo: NewPhoto, tripId: String, stopId: String?, into db: Database) throws {
        try PhotoRefRecord(
            id: UUID().uuidString, tripId: tripId, stopId: stopId,
            phAssetId: photo.assetId, takenAt: photo.takenAt,
            lat: photo.lat, lon: photo.lon,
            isHighlight: photo.isHighlight ? 1 : 0
        ).insert(db)
    }
}

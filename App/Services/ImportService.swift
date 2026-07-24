import Foundation
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine

/// Orchestrates photo-EXIF import (spec §4.7, the Replay MVP's core loop):
/// geotagged photos → clusters → an `imported_photos` trip that flows through
/// the normal Trip Detail / RecapComposer / ExportEngine pipeline unchanged,
/// then best-effort OSRM road-snapping (§4.4). The clustering is pure
/// (`KamomeImportKit`); this layer maps its plan onto the repository. It never
/// touches PhotoKit — the caller supplies `[ImportPhoto]` from a photo source —
/// so it stays deterministically testable.
struct ImportService {
    private let repository: TripRepository
    private let config: TrackingConfig
    private let matcher: RouteMatchService

    init(repository: TripRepository, config: TrackingConfig, matcher: RouteMatchService? = nil) {
        self.repository = repository
        self.config = config
        self.matcher = matcher ?? RouteMatchService(repository: repository, config: config)
    }

    enum ImportError: Error, Equatable {
        /// Fewer than two geotagged photos survived — not a trip (mirrors the
        /// recording-side phantom-trip guard).
        case notEnoughGeotaggedPhotos
    }

    /// Clusters `photos`, persists them as an imported trip with honest
    /// provenance, snaps the route best-effort, and returns the trip id.
    @discardableResult
    func importTrip(title: String, photos: [ImportPhoto]) async throws -> String {
        let clustering = ImportClusteringConfig(
            stopRadiusM: config.photoImport.stopRadiusM,
            stopSplitGapS: config.photoImport.stopSplitGapS,
            minPhotosPerStop: config.photoImport.minPhotosPerStop
        )
        let plan = PhotoImportClusterer.plan(photos: photos, config: clustering)
        guard plan.isRenderable else { throw ImportError.notEnoughGeotaggedPhotos }

        let byId = Dictionary(photos.map { ($0.assetId, $0) }, uniquingKeysWith: { first, _ in first })
        func newPhoto(_ id: String) -> TripRepository.NewPhoto {
            let photo = byId[id]
            return TripRepository.NewPhoto(assetId: id, takenAt: photo?.timestamp, lat: photo?.lat, lon: photo?.lon)
        }

        // One drive segment carries the whole coarse route (the road-trip
        // assumption); OSRM snaps it, low-confidence legs render inferred.
        let segment = TripRepository.NewSegment(
            mode: TransportMode.drive.rawValue,
            startedAt: plan.startedAt,
            endedAt: plan.endedAt,
            points: plan.routePoints.map { TripRepository.NewTrackpoint(ts: $0.timestamp, lat: $0.lat, lon: $0.lon) },
            source: SegmentSource.exif.rawValue
        )
        let stopsWithPhotos = plan.stops.map { stop in
            TripRepository.NewStopWithPhotos(
                stop: TripRepository.NewStop(
                    lat: stop.lat, lon: stop.lon,
                    arrivedAt: stop.arrivedAt, departedAt: stop.departedAt
                ),
                photos: stop.photoAssetIds.map(newPhoto)
            )
        }

        let tripId = try repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: title,
                startedAt: plan.startedAt,
                endedAt: plan.endedAt,
                source: TripSource.importedPhotos.rawValue,
                segments: [segment],
                stopsWithPhotos: stopsWithPhotos,
                routeAttachedPhotos: plan.routeAttachedAssetIds.map(newPhoto)
            )
        )

        // §4.4: snap the drive route to roads, best-effort and idempotent. The
        // shipped `matching.base_url` is "" (disabled) so this is a no-op until
        // an OSRM server exists — the trip is already saved and viewable.
        await matcher.matchTrip(tripId: tripId)
        return tripId
    }
}

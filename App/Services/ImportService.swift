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
            // The favourite flag lands in the existing `is_highlight` column: both
            // mean "this one matters", the deck selector already orders by it, and
            // a user retagging in S4 overwrites it. One concept, one column.
            return TripRepository.NewPhoto(
                assetId: id, takenAt: photo?.timestamp, lat: photo?.lat, lon: photo?.lon,
                isHighlight: photo?.isFavorite ?? false
            )
        }

        // One segment per inter-stop leg (typed-leg pass 2026-07-26), not one
        // per trip: each leg then carries its own transport mode and its own
        // reconstruction verdict, which is what lets the film draw a confidently
        // routed stretch solid and an unroutable one dashed (PD-1). A single
        // trip-wide segment can only ever make one claim about all of it.
        let segments = plan.legs.map { leg in
            TripRepository.NewSegment(
                mode: mode(for: leg).rawValue,
                startedAt: leg.startedAt,
                endedAt: leg.endedAt,
                points: leg.points.map { TripRepository.NewTrackpoint(ts: $0.timestamp, lat: $0.lat, lon: $0.lon) },
                source: SegmentSource.exif.rawValue
            )
        }
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
                segments: segments,
                stopsWithPhotos: stopsWithPhotos,
                routeAttachedPhotos: plan.routeAttachedAssetIds.map(newPhoto)
            )
        )

        // §4.4: reconstruct each drivable leg's road geometry, best-effort and
        // idempotent. The shipped `matching.base_url` is "" (disabled) so this
        // is a no-op until an OSRM server exists — the trip is already saved and
        // viewable, and unreconstructed legs render dashed rather than claiming
        // a road they never proved (PD-2).
        await matcher.matchTrip(tripId: tripId)
        return tripId
    }

    /// Classifies a leg by its implied pace (PD-8). Walking-pace legs stay
    /// `walk` and therefore stay raw: the reconstructor runs a car profile, so
    /// routing a 400 m stroll between two cafés would snap it onto the nearest
    /// road and invent a journey that never happened.
    ///
    /// **Pace is only a signal while the elapsed time was plausibly spent
    /// travelling** (Chiu 2026-08-02). Past `import.pace_unknowable_gap_s` it was
    /// not — an overnight gap is a night's sleep, not slow travel — so the leg
    /// falls back to the same road-trip assumption already made for legs with no
    /// elapsed time at all. Without that, every inter-day leg of a multi-day trip
    /// typed as a walk and drew as a straight line across whatever lay between.
    private func mode(for leg: ImportedLeg) -> TransportMode {
        guard let speed = leg.impliedSpeedKmh,
              leg.endedAt - leg.startedAt <= config.photoImport.paceUnknowableGapS
        else { return .drive }
        return speed <= config.segmentation.speedWalkMaxKmh ? .walk : .drive
    }
}

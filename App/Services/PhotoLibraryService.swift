import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTripComposer
import Photos

/// PhotoKit adapter for §4.3: fetch assets in the trip window, run the pure
/// matcher, persist photo_refs. Limited library access works transparently —
/// fetches simply return the user-selected subset.
final class PhotoLibraryService {
    private let config: TrackingConfig
    private let repository: TripRepository

    init(config: TrackingConfig, repository: TripRepository) {
        self.config = config
        self.repository = repository
    }

    /// Requests read access if needed, then matches photos to the trip.
    /// Calls back on the main queue with the number of matched photos.
    func matchPhotos(
        tripId: String,
        startedAt: Double,
        endedAt: Double,
        stops: [StopRecord],
        completion: @escaping (Int) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard let self, status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            let refs = self.buildRefs(tripId: tripId, startedAt: startedAt, endedAt: endedAt, stops: stops)
            try? self.repository.replacePhotoRefs(tripId: tripId, with: refs)
            DispatchQueue.main.async { completion(refs.count) }
        }
    }

    private func buildRefs(
        tripId: String,
        startedAt: Double,
        endedAt: Double,
        stops: [StopRecord],
        now: () -> Date = Date.init
    ) -> [PhotoRefRecord] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            Date(timeIntervalSince1970: startedAt) as NSDate,
            Date(timeIntervalSince1970: endedAt) as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        let matcherStops = stops.map {
            PhotoMatcher.Stop(id: $0.id, lat: $0.lat, lon: $0.lon, arrivedAt: $0.arrivedAt, departedAt: $0.departedAt)
        }

        var refs: [PhotoRefRecord] = []
        assets.enumerateObjects { asset, _, _ in
            let photo = PhotoMatcher.Photo(
                id: asset.localIdentifier,
                takenAt: asset.creationDate?.timeIntervalSince1970,
                lat: asset.location?.coordinate.latitude,
                lon: asset.location?.coordinate.longitude
            )
            let stopId = PhotoMatcher.stopId(
                for: photo, stops: matcherStops, tripEndedAt: endedAt, config: self.config.photos
            )
            refs.append(PhotoRefRecord(
                id: UUID().uuidString,
                tripId: tripId,
                stopId: stopId,
                phAssetId: asset.localIdentifier,
                takenAt: photo.takenAt,
                lat: photo.lat,
                lon: photo.lon
            ))
        }
        return refs
    }
}

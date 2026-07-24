import Foundation
import KamomeImportKit
import Photos

/// PhotoKit adapter for photo-EXIF import (spec §4.7): fetches geotagged photos
/// in a date range and reduces them to `[ImportPhoto]` for `ImportService`.
/// Keeps PhotoKit confined to this one file (SDK-confinement rule) — the
/// clusterer and `ImportService` never see a `PHAsset`. Limited-library access
/// works transparently: the fetch returns the user-selected subset.
protocol ImportPhotoProviding {
    /// Geotagged image assets taken in `[start, end]`, time-ordered. Assets
    /// without a location are dropped — import needs EXIF GPS. Image bytes are
    /// never read here (reference by identifier only, §3).
    func photos(from start: Date, to end: Date) async -> [ImportPhoto]
}

final class PhotoLibraryImportSource: ImportPhotoProviding {
    func photos(from start: Date, to end: Date) async -> [ImportPhoto] {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                guard status == .authorized || status == .limited else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: Self.fetch(from: start, to: end))
            }
        }
    }

    private static func fetch(from start: Date, to end: Date) -> [ImportPhoto] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            start as NSDate, end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var photos: [ImportPhoto] = []
        assets.enumerateObjects { asset, _, _ in
            guard let location = asset.location, let date = asset.creationDate else { return }
            photos.append(ImportPhoto(
                assetId: asset.localIdentifier,
                timestamp: date.timeIntervalSince1970,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude
            ))
        }
        return photos
    }
}

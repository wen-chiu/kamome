import Foundation
import KamomeImportKit
import Photos

/// **What set of photographs a trip is reconstructed from** (spec §4.7).
///
/// Generalised from a bare `(start, end)` pair on 2026-08-15 rather than adding a
/// second fetch method, for the same reason `RecapMode` is one value instead of
/// three booleans: when a third source arrives, the compiler names every call site
/// that has to think about it. Switch exhaustively, never with a `default:`.
///
/// The date range remains the **default** path, not a legacy one — most trips are
/// still "the days I was away", and an album only helps someone who already keeps
/// one.
enum ImportQuery: Equatable {
    /// Every geotagged photo taken in `[from, to]`, whatever album it is in.
    case dateRange(from: Date, to: Date)
    /// Every geotagged photo in one album, whatever day it was taken.
    ///
    /// **An album is not necessarily one trip.** `ImportService` builds a single
    /// trip from whatever set it is handed, and `stop_split_gap_s` splits *stops*,
    /// not trips — so an album holding two separate holidays becomes one trip with
    /// an absurd leg between them. The importer does not silently produce that: the
    /// album's own date span is shown before import so the user can see it. Whether
    /// to warn or offer to split is an open design question (Chiu 2026-08-15).
    case album(id: String)
}

/// One photo album, reduced to what the picker needs. Deliberately a plain value:
/// no `PHAssetCollection` leaves this file, the same rule that keeps `PHAsset`
/// out of the clusterer.
struct PhotoAlbum: Equatable, Identifiable {
    let id: String
    let title: String
    /// Images in the album — **not** how many are geotagged, which is only known
    /// after fetching. Miyakojima's own folder was 53 geotagged of 406 files, so
    /// this number is an upper bound on what a trip can be built from.
    let photoCount: Int
    /// Oldest and newest capture dates in the album, or nil for an empty album.
    /// This is the span the user is shown before importing.
    let earliest: Date?
    let latest: Date?
}

/// PhotoKit adapter for photo-EXIF import (spec §4.7): fetches geotagged photos
/// for an `ImportQuery` and reduces them to `[ImportPhoto]` for `ImportService`.
/// Keeps PhotoKit confined to this one file (SDK-confinement rule) — the
/// clusterer and `ImportService` never see a `PHAsset`. Limited-library access
/// works transparently for photos: the fetch returns the user-selected subset.
protocol ImportPhotoProviding {
    /// Geotagged image assets matching `query`, time-ordered. Assets without a
    /// location are dropped — import needs EXIF GPS. Image bytes are never read
    /// here (reference by identifier only, §3).
    func photos(matching query: ImportQuery) async -> [ImportPhoto]

    /// The user's albums, newest content first.
    ///
    /// ⚠️ **Limited Photo Library returns a different world.** Under `.limited`
    /// the system exposes only the assets the user picked, so album membership is
    /// mostly invisible and this list is short or empty — that is PhotoKit
    /// behaving correctly, not an error, and the UI says so rather than showing an
    /// empty list with no explanation.
    func albums() async -> [PhotoAlbum]
}

final class PhotoLibraryImportSource: ImportPhotoProviding {
    func photos(matching query: ImportQuery) async -> [ImportPhoto] {
        await authorized { Self.fetchPhotos(matching: query) } ?? []
    }

    func albums() async -> [PhotoAlbum] {
        await authorized { Self.fetchAlbums() } ?? []
    }

    /// One authorization gate for both fetches. `.limited` is allowed through on
    /// purpose: it returns the user-selected subset, which is a smaller library
    /// rather than a failure.
    private func authorized<T>(_ work: @escaping () -> T) async -> T? {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                guard status == .authorized || status == .limited else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: work())
            }
        }
    }

    private static func fetchPhotos(matching query: ImportQuery) -> [ImportPhoto] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets: PHFetchResult<PHAsset>
        switch query {
        case let .dateRange(from, to):
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@", from as NSDate, to as NSDate
            )
            assets = PHAsset.fetchAssets(with: .image, options: options)
        case let .album(id):
            guard let collection = Self.collection(id: id) else { return [] }
            // `mediaType` cannot go in a collection fetch's predicate, so images
            // are filtered when the assets are reduced below — same result, and
            // one place that decides what an importable asset is.
            assets = PHAsset.fetchAssets(in: collection, options: options)
        }

        var photos: [ImportPhoto] = []
        assets.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image,
                  let location = asset.location,
                  let date = asset.creationDate else { return }
            photos.append(ImportPhoto(
                assetId: asset.localIdentifier,
                timestamp: date.timeIntervalSince1970,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                isFavorite: asset.isFavorite
            ))
        }
        return photos
    }

    private static func collection(id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id], options: nil
        ).firstObject
    }

    /// User albums and shared albums, each reduced to `PhotoAlbum`. Smart albums
    /// (Recents, Favourites, Screenshots…) are deliberately excluded: they are not
    /// journeys, and "Recents" as a trip is the date-range path with extra steps.
    private static func fetchAlbums() -> [PhotoAlbum] {
        var albums: [PhotoAlbum] = []
        for type in [PHAssetCollectionType.album] {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: type, subtype: .any, options: nil
            )
            collections.enumerateObjects { collection, _, _ in
                guard let album = Self.reduce(collection) else { return }
                albums.append(album)
            }
        }
        // Newest trip first: the album someone wants to import is almost always
        // the one they just came home from.
        return albums.sorted { ($0.latest ?? .distantPast) > ($1.latest ?? .distantPast) }
    }

    private static func reduce(_ collection: PHAssetCollection) -> PhotoAlbum? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        var earliest: Date?
        var latest: Date?
        var images = 0
        assets.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image else { return }
            images += 1
            guard let date = asset.creationDate else { return }
            if earliest == nil { earliest = date }
            latest = date
        }
        guard images > 0 else { return nil }

        return PhotoAlbum(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "",
            photoCount: images,
            earliest: earliest,
            latest: latest
        )
    }
}

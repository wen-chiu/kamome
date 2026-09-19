import KamomePersistence
import Photos
import SwiftUI

/// Small horizontal run of photo thumbnails for timeline rows.
struct PhotoStrip: View {
    let photos: [PhotoRefRecord]
    let maxThumbnails: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(photos.prefix(maxThumbnails), id: \.id) { photo in
                PhotoThumbnail(assetId: photo.phAssetId, isHighlight: photo.isHighlight == 1)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if photos.count > maxThumbnails {
                Text("+\(photos.count - maxThumbnails)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Loads one PhotoKit thumbnail; a deleted or unavailable asset renders the
/// placeholder tile instead of failing (§3 rules). Never reads more than
/// `targetPx` of an image, so the timeline's memory is bounded by tile count ×
/// tile size, not by the size of the photographs.
struct PhotoThumbnail: View {
    let assetId: String
    var isHighlight = false
    /// Longest side requested from PhotoKit, in pixels. The default is the size
    /// the timeline rows have always asked for; the Journey Discovery beta's
    /// larger tiles pass their own.
    var targetPx: Int = 100

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            }
            if isHighlight {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .padding(2)
            }
        }
        .task(id: "\(assetId)-\(targetPx)") { await loadThumbnail() }
    }

    /// A preview, not the photo: a few hundred pixels, fetched with network access
    /// so an iCloud-only photo shows a picture instead of a grey tile. PhotoKit
    /// serves a derivative at `targetPx`, not the original, and the request is
    /// cancelled with this task when the tile scrolls away.
    private func loadThumbnail() async {
        // A passive thumbnail must never trigger the system photos prompt;
        // asking is the matcher flow's job. Undetermined → placeholder.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return } // deleted → placeholder stays
        let result = await PhotoKitImageLoader.image(
            for: asset, targetPx: targetPx, profile: .preview, allowNetwork: true
        )
        if case let .loaded(loaded) = result { image = loaded }
    }
}

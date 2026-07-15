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
/// placeholder tile instead of failing (§3 rules).
struct PhotoThumbnail: View {
    let assetId: String
    var isHighlight = false

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
        .task(id: assetId) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        // A passive thumbnail must never trigger the system photos prompt;
        // asking is the matcher flow's job. Undetermined → placeholder.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return } // deleted → placeholder stays
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        image = await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 100, height: 100),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                guard !resumed else { return } // opportunistic can call twice
                resumed = true
                continuation.resume(returning: result)
            }
        }
    }
}

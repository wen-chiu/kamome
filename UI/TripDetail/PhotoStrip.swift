import KamomePersistence
import Photos
import SwiftUI

/// Small horizontal run of photo thumbnails for timeline rows.
struct PhotoStrip: View {
    let photos: [PhotoRefRecord]
    let maxThumbnails: Int
    var side: CGFloat = 36

    var body: some View {
        HStack(spacing: 4) {
            ForEach(photos.prefix(maxThumbnails), id: \.id) { photo in
                PhotoThumbnail(assetId: photo.phAssetId, isHighlight: photo.isHighlight == 1, targetPx: Int(side * 3))
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side / 6, style: .continuous))
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
    enum Placeholder {
        /// The grey tile with a photo glyph — a strip's missing thumbnail.
        case tile
        /// A soft gradient and the gull — a card with no photograph to show.
        case cinematic
    }

    let assetId: String
    var isHighlight = false
    /// Longest side requested from PhotoKit, in pixels.
    var targetPx: Int = 100
    var placeholder: Placeholder = .tile

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Color.clear.overlay(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
            } else {
                switch placeholder {
                case .tile:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.secondary.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                case .cinematic:
                    Self.cinematicPlaceholder
                }
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

    /// Sky over sand with the gull — what a journey looks like before its
    /// photographs load, or when they cannot.
    static var cinematicPlaceholder: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.15), Color(.systemFill)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(alignment: .center) {
            Image(systemName: "bird")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
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
        let side = CGFloat(max(targetPx, 1))
        image = await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
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

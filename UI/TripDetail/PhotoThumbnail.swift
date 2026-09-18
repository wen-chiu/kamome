import KamomePersistence
import Photos
import SwiftUI

/// Loads one PhotoKit thumbnail; a deleted or unavailable asset renders the
/// placeholder tile instead of failing (§3 rules).
struct PhotoThumbnail: View {
    let assetId: String
    var isHighlight = false
    /// Longest side requested from PhotoKit, in pixels.
    var targetPx: Int = 100

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
                // A missing thumbnail is a quiet tile, never a broken-image
                // glyph: the asset being in iCloud or deleted is not an error
                // the reader can act on, and the row beside it still reads.
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.18))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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

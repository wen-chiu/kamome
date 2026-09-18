import KamomeImportKit
import KamomePersistence

/// Turns stored photo refs into the pure cover selector's candidates, so the
/// detail's hero and the home card pick the same photographs for one journey.
enum PhotoCoverSelectorBridge {
    static func select(_ photos: [PhotoRefRecord], count: Int) -> [String] {
        PhotoCoverSelector.select(
            photos.map { PhotoCoverSelector.Candidate(assetId: $0.phAssetId, isHighlight: $0.isHighlight == 1) },
            count: count
        )
    }
}

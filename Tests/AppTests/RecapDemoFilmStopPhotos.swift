import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence

/// Split out of `RecapDemoFilmTests.importedRecap` (lint length only, Chiu
/// 2026-08-07).
extension RecapDemoFilmTests {
    /// What `stopPhotoSelections` computes per stop — grouped so the three
    /// per-stop dictionaries travel together instead of as a 3-tuple.
    struct StopPhotoSelections {
        let photosByStop: [String: [PhotoRef]]
        let rawPhotoCounts: [String: Int]
        let favoriteCounts: [String: Int]
    }

    /// **The app's own selection** (`RecapModel.selectStopPhotoRefs`): highlight
    /// first, then evenly spread across the visit, capped at `deck_max_photos`.
    /// This used to be a hardcoded `.prefix(3)`, which meant no review render
    /// could ever show what the shipped app shows — a stop the app gives eight
    /// photographs was reviewed with three.
    static func stopPhotoSelections(
        detail: TripRepository.TripDetail, full: TrackingConfig
    ) -> StopPhotoSelections {
        var photosByStop: [String: [PhotoRef]] = [:]
        var rawPhotoCounts: [String: Int] = [:]
        var favoriteCounts: [String: Int] = [:]
        for stop in detail.stops {
            let atStop = detail.photos.filter { $0.stopId == stop.id }
            rawPhotoCounts[stop.id] = atStop.count
            favoriteCounts[stop.id] = atStop.filter { $0.isHighlight != 0 }.count
            let ordered = detail.photos
                .filter { $0.stopId == stop.id }
                .sorted { lhs, rhs in
                    if lhs.isHighlight != rhs.isHighlight { return lhs.isHighlight > rhs.isHighlight }
                    return (lhs.takenAt ?? 0) < (rhs.takenAt ?? 0)
                }
                .map(\.phAssetId)
            let selected = PhotoDeckSelector.evenlySpread(
                ordered, min: full.photoImport.deckMinPhotos, max: full.photoImport.deckMaxPhotos
            )
            if !selected.isEmpty { photosByStop[stop.id] = selected.map(PhotoRef.asset) }
        }
        return StopPhotoSelections(
            photosByStop: photosByStop, rawPhotoCounts: rawPhotoCounts, favoriteCounts: favoriteCounts
        )
    }
}

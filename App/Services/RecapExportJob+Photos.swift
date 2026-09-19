import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence

/// Deck photo selection and warming. Moved from `RecapModel` unchanged
/// (Chiu 2026-09-10); the only difference is that the shortfall now travels out
/// through the channel instead of onto a view's model, so it survives the sheet
/// being closed.
extension RecapExportJob {
    /// Decodes every deck photo up front — downloading the ones that live only in
    /// iCloud — so the film is rendered from photos that are already in hand and
    /// a stop that will still render a blank card is reported before the export
    /// rather than discovered in the finished film.
    ///
    /// Runs **after** the user has tapped Export and **after** composition, so
    /// `trip.stops.flatMap(\.photos)` is exactly what the film draws: the stop
    /// selection and per-stop allocation have already cut the library down to it
    /// (Chiu 2026-09-19). Nothing else is ever requested.
    func warmDeckPhotos(
        trip: RecapTrip, style: RecapStyle,
        resolver: PhotoLibraryPhotoResolver, channel: RecapExportChannel
    ) async {
        channel.photoShortfall(nil)
        guard request.photosEnabled else { return }
        let targetPx = Int(CGFloat(config.export.frameWidthPx) * style.deckPhotoMaxWidthFraction)
        let preload = channel.photoPreload
        // Progress hops to main as fire-and-forget tasks; without this, one still
        // queued when the warm ends could land after `preload(nil)` and leave
        // "Downloading from iCloud" on screen for the whole render.
        let warmEnded = ExportCancelFlag()
        let warmed = await resolver.warm(
            trip.stops.flatMap(\.photos), targetPx: max(targetPx, 1),
            timeoutS: config.photos.icloudFetchTimeoutS,
            progress: { progress in Task { @MainActor in if !warmEnded.isSet { preload(progress) } } },
            shouldContinue: channel.shouldContinue
        )
        warmEnded.set()
        preload(nil)
        guard channel.shouldContinue() else { return }
        if warmed.downloaded > 0 {
            KamomeLog.recap.notice("""
                deck photos: \(warmed.downloaded) of \(warmed.requested) downloaded from iCloud, \
                \(warmed.resolved - warmed.downloaded) already on this device
                """)
        }
        guard warmed.missing > 0 else { return }
        channel.photoShortfall(warmed)
        KamomeLog.recap.error("""
            \(warmed.missing) of \(warmed.requested) deck photos could not be loaded \
            (\(warmed.inCloud) are in iCloud and could not be downloaded) — those stops will \
            render blank cards. The route is unaffected: EXIF place and time need no download.
            """)
    }

    /// Every stop's **raw** photograph count — what `StopWeighting` judges the
    /// place on, before `deck_max_photos` caps what the film can show.
    func rawPhotoCounts(detail: TripRepository.TripDetail) -> [String: Int] {
        var counts: [String: Int] = [:]
        for photo in detail.photos {
            guard let stopId = photo.stopId else { continue }
            counts[stopId, default: 0] += 1
        }
        return counts
    }

    /// Favourited photographs per stop — `PHAsset.isFavorite` at import time,
    /// stored in `is_highlight`. Zero on trips imported before that landed.
    func favoriteCounts(detail: TripRepository.TripDetail) -> [String: Int] {
        var counts: [String: Int] = [:]
        for photo in detail.photos where photo.isHighlight != 0 {
            guard let stopId = photo.stopId else { continue }
            counts[stopId, default: 0] += 1
        }
        return counts
    }

    /// Selects each stop's deck photo *refs* (§5): highlight first, then the rest
    /// evenly spread across the visit, capped at `deck_max_photos` so a
    /// photo-dense stop samples the whole visit rather than just its first burst
    /// (`PhotoDeckSelector`, shared with import). Pure data — no PhotoKit, no
    /// bitmaps; the render layer resolves the refs.
    func selectStopPhotoRefs(detail: TripRepository.TripDetail) -> [String: [PhotoRef]] {
        var result: [String: [PhotoRef]] = [:]
        for stop in detail.stops {
            let ordered = detail.photos
                .filter { $0.stopId == stop.id }
                .sorted { lhs, rhs in
                    if lhs.isHighlight != rhs.isHighlight { return lhs.isHighlight > rhs.isHighlight }
                    return (lhs.takenAt ?? 0) < (rhs.takenAt ?? 0)
                }
                .map(\.phAssetId)
            let selected = PhotoDeckSelector.evenlySpread(
                ordered,
                min: config.photoImport.deckMinPhotos,
                max: config.photoImport.deckMaxPhotos
            )
            if !selected.isEmpty { result[stop.id] = selected.map(PhotoRef.asset) }
        }
        return result
    }
}

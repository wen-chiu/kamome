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
        let preload = channel.photoPreload
        // Progress hops to main as fire-and-forget tasks; without this, one still
        // queued when the warm ends could land after `preload(nil)` and leave
        // "Downloading from iCloud" on screen for the whole render.
        let warmEnded = SharedFlag()
        let warmed = await resolver.warm(
            trip.stops.flatMap(\.photos),
            targetSize: Self.deckPhotoSize(frameWidthPx: config.export.frameWidthPx, style: style),
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

    /// **The size a deck photograph is decoded at: the card it fills** (#279).
    ///
    /// The card is portrait — `deckPhotoMaxWidthFraction` of the frame wide,
    /// `deckPhotoAspect` times that tall — and the photograph is drawn to fill
    /// it. Decoded to fill a *square* of the card's width, a landscape
    /// photograph came back only as tall as the card is wide (626 of 835 px at
    /// 1080) and was upscaled 1.31× into it, soft in every film. Asked to fill
    /// the card itself, every photograph arrives at least the card's size on
    /// both sides; a portrait one is the same size as before.
    static func deckPhotoSize(frameWidthPx: Int, style: RecapStyle) -> CGSize {
        let width = max(CGFloat(frameWidthPx) * style.deckPhotoMaxWidthFraction, 1).rounded(.up)
        return CGSize(width: width, height: (width * style.deckPhotoAspect).rounded(.up))
    }
}

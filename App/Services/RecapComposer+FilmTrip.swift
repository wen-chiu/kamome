import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer

/// **The one way a trip becomes a film's data** — the export composes with it,
/// and the export sheet measures the film's length with it (Chiu 2026-09-29), so
/// the length the sheet says is the length the export builds.
extension RecapComposer {
    /// The composed trip, and what composing it left out (for the export's log).
    struct FilmComposition {
        let trip: RecapTrip
        /// Legs and stops after the flight home, which the film does not show.
        let droppedSegments: Int
        let droppedStops: Int
        /// The photo pick used the analysis (ADR 2026-09-25 (d)), not the time order.
        let analysed: Bool
    }

    static func filmComposition(
        detail: TripRepository.TripDetail, config: TrackingConfig, photosEnabled: Bool, length: FilmLength
    ) -> FilmComposition? {
        let stats = TripStats.from(jsonString: detail.trip.statsJson)
        // Deck photo refs are selected here (data); the resolver loads the
        // bitmaps. The counts are read either way: which stops the film presents
        // must not change because photo cards are switched off, only whether they show.
        let photos = photoInputs(detail: detail, analysis: config.photoAnalysis)
        let deck = RecapDeck(
            photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS,
            labelLeadS: config.export.deckLabelLeadS, photoMinHoldS: config.export.deckPhotoMinHoldS
        )
        // The film ends at the destination (ADR 2026-09-01): the flight home and
        // everything after it come off here, before anything is classified.
        let film = filmRecords(
            segments: detail.segments, stops: detail.stops,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM,
            homeRadiusM: config.discovery.awayRadiusM
        )
        // Typed legs (Fable review 2026-07-26): each stretch reaches the film
        // with its own transport mode and provenance, so a leg Kamome could not
        // reconstruct renders visibly as a guess rather than as road (PD-1).
        let legs = legs(
            from: film.segments, epsilonM: config.simplify.epsilonM, matchedEpsilonM: config.matching.displayEpsilonM
        )
        guard let trip = trip(
            trip: detail.trip, legs: legs, stops: film.stops, stats: stats,
            photosByStop: photosEnabled ? photos.byStop : [:], deck: deck, stopHoldS: config.export.stopHoldS,
            rawPhotoCounts: photos.rawCounts,
            favoriteCounts: photos.starredCounts,
            highlightedAssets: photos.highlighted,
            pickedAssets: photos.picked, pickedCounts: photos.pickedCounts,
            analysis: photos.analysis,
            highlightMaxPhotos: config.photoImport.deckHighlightMaxPhotos,
            weighting: config.export,
            length: length,
            everyLegRoutabilityEstablished: everyLegRoutabilityEstablished(film.segments),
            clock: TripClock(stops: detail.stops),
            title: TripTitle.film(detail.trip)
        ) else { return nil }
        return FilmComposition(
            trip: trip,
            droppedSegments: detail.segments.count - film.segments.count,
            droppedStops: detail.stops.count - film.stops.count,
            analysed: photos.analysis != nil
        )
    }

    /// **How long the film will run, measured** (Chiu 2026-09-29): the timeline
    /// the export builds, over the trip it composes, on the map region it
    /// resolves. Travel is earned by what crosses the screen (ADR file
    /// 2026-09-28), so the plan alone (`estimatedFilmS`) can only say an upper
    /// bound. Still an estimate on the sheet: a trip whose routing has not
    /// answered is measured on its straight legs, and the export routes first.
    static func measuredFilmS(trip: RecapTrip, config: TrackingConfig.Export) -> Double? {
        let tripBox = GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) })
        let establishing = tripBox.flatMap { RecapMapRegionResolver.resolve(covering: $0) }.map {
            RecapBounds(
                minLat: $0.bounds.minLat, minLon: $0.bounds.minLon, maxLat: $0.bounds.maxLat, maxLon: $0.bounds.maxLon
            )
        }
        return LinearTimeline(trip: trip, config: config, establishing: establishing)?.durationS
    }
}
